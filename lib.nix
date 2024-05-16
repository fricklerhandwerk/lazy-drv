/**
  Build executables from Nix derivations on demand.

  # Motivation

  Nix does not allow on-demand [realisation](https://nix.dev/manual/nix/2.19/glossary#gloss-realise) of store paths.
  But sometimes it would be nice to have a large closure only realised when it's actually accessed, for example when a rarely-used helper command is run.

  This tool is inspired by [TVL's `lazy-deps`](https://cs.tvl.fyi/depot@0c0edd5928d48c9673dd185cd332f921e64135e7/-/blob/nix/lazy-deps/default.nix).

  It trades saving initial build time against adding a startup time overhead.
  And it meshes well with [`attr-cmd`](https://github.com/fricklerhandwerk/attr-cmd), a library for producing command line programs from attribute sets.

  # Installation

  ```shell-session
  nix-shell -p npins
  npins init
  npins add github fricklerhandwerk lazy-drv -b main
  ```

  ```nix
  # default.nix
  let
    sources = import ./npins;
  in
  {
    pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
    lazy-drv ? import sources.lazy-drv { inherit pkgs system; },
    system ? builtins.currentSystem,
  }:
  let
    lib = pkgs.lib // lazy-drv.lib;
  in
  pkgs.callPackage ./example.nix { inherit lib; }
  ```
  # Future work

  Obviously this is just a cheap trick that can't do more than run selected commands from derivations.

  More fancy things, such as lazily exposing `man` pages or other auxiliary data from a package, would probably require integration into a configuration management framework like NixOS, since every tool in question would have to play along.

  This could indeed be quite powerful:
  Imagine wiring up `man` to accept an additional option `--nixpkgs`.
  It would then first inspect `$MANPATH`, and on failure leverage [`nix-index`](https://github.com/nix-community/nix-index) to realise the appropriate derivation on the fly.

  One current limitation is that the Nix expression underlying the lazy derivation still needs to evaluated.
  This can become costly for large expressions.
  Another layer of indirection, which also defers evaluation, could be added to avoid that.
*/
{ lib, symlinkJoin, writeShellApplication }:
rec {
  /**
    Replace derivations in an attribute set with calls to `nix-build` on these derivations.

    Input attributes are the same as in the second argument to [`lazify`](#function-library-lib.lazy-drv.lazify).

    :::{.example}

    # Make derivations in an attribute set build lazily

    ```nix
    # example.nix
    { pkgs, lib }:
    let
      example = pkgs.writeText "example-output" "Built on demand!";

      lazy = lib.lazy-drv.lazy-build {
        source = "${with lib.fileset; toSource {
          root = ./.;
          fileset = unions [ ./default.nix ];
        }}";
        attrs = { inherit example; };
      };
    in
    {
      inherit example;
      shell = pkgs.mkShellNoCC {
        packages = with lib; collect isDerivation lazy;
      };
    }
    ```

    ```console
    $ nix-shell -A shell -I lazy-drv=https://github.com/fricklerhandwerk/lazy-drv/tarball/master
    [nix-shell:~]$ example-output
    this derivation will be built:
      /nix/store/...-example-output.drv
    building '/nix/store/...-example-output.drv'...
    [nix-shell:~]$ cat result
    Built on demand!
    ```
    :::
  */
  lazy-build =
    let
      build = nix-build: drv:
        writeShellApplication { inherit (drv) name; text = ''exec ${nix-build} "$@"''; };
    in
    lazify build;

  /**
    Replace derivations in an attribute set with calls to the executable specified in each derivation's `meta.mainProgram`.

    Input attributes are the same as in the second argument to [`lazify`](#function-library-lib.lazy-drv.lazify-attrs).

    :::{.example}

    # Build a derivation on demand and run its main executable

    ```nix
    # example.nix
    { pkgs, lib }:
    let
      example = pkgs.writeShellScriptBin "example-command" "echo I am lazy";

      lazy = lib.lazy-drv.lazy-run {
        source = "${with lib.fileset; toSource {
          root = ./.;
          fileset = unions [ ./. ];
        }}";
        attrs = { inherit example; };
        nix-build-args = [ "--no-out-link" ];
      };
    in
    {
      inherit example;
      shell = pkgs.mkShellNoCC {
        packages = with lib; collect isDerivation lazy;
      };
    }
    ```

    ```console
    $ nix-shell -A shell -I lazy-drv=https://github.com/fricklerhandwerk/lazy-drv/tarball/master
    [nix-shell:~]$ example-command
    this derivation will be built:
      /nix/store/...-example-command.drv
    building '/nix/store/...-example-command.drv'...
    I am lazy
    ```
    :::
  */
  lazy-run =
    let
      run = nix-build: drv:
        writeShellApplication {
          name = drv.meta.mainProgram;
          text = ''exec "$(${nix-build} --no-out-link)"/bin/${drv.meta.mainProgram} "$@"'';
        };
    in
    lazify run;

  /**
    Make a command line that calls `nix-build` on an `attrpath` in a `source` file.

    # Arguments

    - `source` (path or string)

      Path to the Nix file declaring the derivation to realise.
      If the expression in the file is a function, it must take an attribute set where all values have defaults.

      If the path points to a directory, the complete directory this file lives in will be copied into the store.
      The Nix expression must not access files outside of this directory.

      If the path points to a single file, the Nix experession in the file must not refer to other files.

      The most robust and efficient approach is using a file from a [file set](https://nixos.org/manual/nixpkgs/stable/#sec-functions-library-fileset).

    - `attrpath` (list of strings)

      The [attribute path](https://nix.dev/manual/nix/2.19/language/operators#attribute-selection) to the derivation in the expression at `source` to wrap, denoted as a list of path components.

    - `nix` (derivation or string, optional)

      Path to a Nix package that has the executable `nix-build`.
      If not set, the command name `nix-build` is used.

    - `nix-build-args` (list of strings, optional)

      Default: `[ ]`

      [Command-line arguments](https://nix.dev/manual/nix/2.19/command-ref/nix-build#options) to pass to `nix-build` for the on-demand realisation.

    - `nix-build-env` (attribute set, optional)

      Default: `{ }`

      [Environment variables](https://nix.dev/manual/nix/2.19/command-ref/nix-build#common-environment-variables) to set on the invocation of `nix-build` for the on-demand realisation.

    :::{.example}

    # Generate a command line

    ```nix
    # example.nix
    { pkgs, lib }:
    lib.lazy-drv.nix-build {
      source = with lib.fileset; toSource {
        root = ./.;
        fileset = unions [ ./default.nix ./npins ];
      }};
      attrpath = [ "foo" "bar" ];
      nix-build-env = { NIX_PATH=""; };
      nix-build-args = [ "--no-out-link" ];
    }
    ```

    ```console
    $ nix-instantiate --eval
    "NIX_PATH= nix-build /nix/store/...-source -A foo.bar --no-out-link"
    ```
    :::
  */
  nix-build =
    { source
    , attrpath
    , nix ? null
    , nix-build-args ? [ ]
    , nix-build-env ? { }
    }:
      with lib;
      join " " (filter (x: x != "") [
        (join " " (mapAttrsToList (k: v: "${k}=${toString v}") nix-build-env))
        "${optionalString (!isNull nix) "${nix}/bin/"}nix-build ${source} -A ${join "." attrpath}"
        (join " " nix-build-args)
      ]);

  /**
    Make derivations in an attribute set lazy.

    # Arguments

    1. `lazifier` (`[String] -> Derivation -> a`)

       This function is given a command line as produced by the [`nix-build` function](#function-library-lib.lazy-drv.nix-build), and the derivation it's supposed to operate on.
       It can return anything, but in practice would produce a derivation with a shell script that executes the command line and processes the build result.
       See the sources of [`lazy-build`](#function-library-lib.lazy-drv.lazy-build) and [`lazy-run`](#function-library-lib.lazy-drv.lazy-run) for examples.

    2. An attribute set:

       - `attrs` (attribute set)

         Nested attribute set of derivations.
         It must correspond to a top-level attribute set in the expression at `source`.

       - `source` (path or string)

         Path to the Nix file declaring the attribute set `attrs`.

       - `nix` (derivation or string, optional)

         Same as the `nix` attribute in the argument to the [`nix-build` function](#function-library-lib.lazy-drv.nix-build).

       - `nix-build-args` (list of strings, optional)

         Default: `[ ]`

         Same as the `nix-build-args` attribute in the argument to the [`nix-build` function](#function-library-lib.lazy-drv.nix-build).

       - `nix-build-env` (attribute set, optional)

         Default: `{ }`

         Same as the `nix-build-env` attribute in the argument to the [`nix-build` function](#function-library-lib.lazy-drv.nix-build).
  */
  lazify = lazifier:
    { source
    , attrs
    , nix ? null
    , nix-build-args ? [ ]
    , nix-build-env ? { }
    }:
    let
      lazificator = attrpath: drv:
        assert attrpath-exists "lazify" source attrpath;
        let
          build-command = nix-build { inherit source attrpath nix nix-build-env nix-build-args; };
        in
        lazifier build-command drv;
    in
    assert file-is-autocallable "lazify" source;
    mapAttrsRecursiveCond' lib.isDerivation lazificator attrs;

  /**
    Apply function `f` to all nested attributes in attribute set `attrs` which satisfy predicate `pred`.
  */
  mapAttrsRecursiveCond' = pred: f: attrs:
    with lib;
    mapAttrsRecursiveCond
      (value: !pred value)
      (attrpath: value: if pred value then f attrpath value else value)
      attrs;

  file-is-autocallable = context: path:
    with lib;
    if !pathExists path then
      throw "${context}: source file '${toString path}' does not exist"
    else if pathIsDirectory path && !pathExists "${path}/default.nix" then
      throw "${context}: source file '${toString path}/default.nix' does not exist"
    else if isFunction (import path) then
      all id
        (mapAttrsToList
          (name: value:
            if value then value else
            throw "${context}: function argument '${name}' in '${toString path}' must have a default value"
          )
          (__functionArgs (import path)))
    else true;

  attrpath-exists = context: path: attrpath:
    if lib.hasAttrByPath attrpath (import path { }) then true else
    throw "${context}: attribute path '${join "." attrpath}' does not exist in '${toString path}'";

  join = lib.concatStringsSep;

  # these are from earlier attempts that involved parsing string or list representations of attribute paths.
  # it's not a great idea to do that in my opinion, but if you really need to do it, you may find this helpful:
  matchAttrName = string: lib.strings.match "^([a-zA-Z_][a-zA-Z0-9_'-]*|\"[^\"]*\")$" string;
  isAttrPathString = string:
    with lib;
    join "." (concatMap matchAttrName (splitString "." string)) == string;
  isAttrPathList = list:
    with lib; all (x: x != null) (map matchAttrName list);
}
