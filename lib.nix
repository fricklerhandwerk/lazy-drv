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

    Input attributes are the union of the second argument to [`lazify`](#function-library-lib.lazy-drv.lazify) and [`nix-build`](#function-library-lib.lazy-drv.nix-build).

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
          fileset = unions [ ./example.nix ];
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
    { source
    , attrs
    , predicate ? lib.isDerivation
    , nix ? null
    , nix-build-args ? [ ]
    , nix-build-env ? { }
    }:
    let
      build = attrpath: drv:
        let
          result = nix-build { inherit source attrpath nix nix-build-args nix-build-env; };
        in
        writeShellApplication { inherit (drv) name; text = ''exec ${result} "$@"''; };
    in
    lazify build { inherit source attrs predicate; };

  /**
    Replace derivations in an attribute set with calls to the executable specified in each derivation's `meta.mainProgram`.

    Input attributes are the union of the second argument to [`lazify`](#function-library-lib.lazy-drv.lazify) (except `predicate`, since one can only run the executable from a single derivation) and [`nix-build`](#function-library-lib.lazy-drv.nix-build) (where `nix-build-args` defaults to `[ "--no-out-link" ]`, since one usually doesn't want the `result` symlink).

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
          fileset = unions [ ./example.nix ];
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
    [nix-shell:~]$ example-command
    this derivation will be built:
      /nix/store/...-example-command.drv
    building '/nix/store/...-example-command.drv'...
    I am lazy
    ```
    :::
  */
  lazy-run =
    { source
    , attrs
    , nix ? null
    , nix-build-args ? [ "--no-out-link" ]
    , nix-build-env ? {}
    }:
    let
      run = attrpath: drv:
        let
          result = nix-build { inherit source attrpath nix nix-build-args nix-build-env; };
        in
        writeShellApplication {
          name = drv.meta.mainProgram;
          text = ''exec "$(${result})"/bin/${drv.meta.mainProgram} "$@"'';
        };
    in
    lazify run { inherit source attrs; };

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
    Apply a function to each leaf attribute in a nested attribute set, which must come from a Nix file that is accessible to `nix-build`.

    # Arguments

    1. `lazifier` (`[String] -> a -> b`)

       This function is given the attribute path in the nested attribute set being processed, and the value it's supposed to operate on.
       It is ensured that the attribute path exists in the given `source` file, and that this `source` file can be processed by `nix-build`.

       The function can return anything.
       In practice it would usually produce a derivation with a shell script that runs `nix-build` on the attribute path in the source file, and processes the build result.

    2. An attribute set:

       - `source` (path or string)

         Path to the Nix file declaring the attribute set `attrs`.
         The Nix file must be accessible to `nix-build`:
         - The path must exist in the file system
         - If it leads to a directory instead of a Nix file, that directory must contain `default.nix`
         - If the Nix file contains a function, all its arguments must have default values

       - `attrs` (attribute set)

         Nested attribute set of derivations.
         It must correspond to a top-level attribute set in the expression at `source`.

       - `predicate` (`a -> bool`, optional)

         A function to determine what's a leaf attribute.
         Since the intended use case is to create a `nix-build` command line, one meaningful alternative to the default value is [`isAttrsetOfDerivations`](#function-library-lib.lazy-drv.isBuildable).

         Default: [`lib.isDerivation`](https://nixos.org/manual/nixpkgs/stable/#function-library-lib.attrsets.isDerivation)
  */
  lazify = lazifier:
    { source
    , attrs
    , predicate ? lib.isDerivation
    }:
    let
      lazificator = attrpath: value:
        assert attrpath-exists "lazify" source attrpath;
        lazifier attrpath value;
    in
    assert file-is-autocallable "lazify" source;
    mapAttrsRecursiveCond' predicate lazificator attrs;

  /**
    Check if the given value is a derivation or an attribute set of derivations.

    This emulates what `nix-build` expects as the contents of `default.nix`.
  */
  isBuildable = value:
    with lib; isAttrs value && (value.type or null == "derivation" || all isDerivation (attrValues value));

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
    let
      imported = import path;
      source = if lib.isFunction imported then imported { } else imported;
    in
    if lib.hasAttrByPath attrpath source then true else
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
