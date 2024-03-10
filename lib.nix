{ lib, symlinkJoin, writeShellApplication }:
rec {
  /**
    Make a command line that calls `nix-build` on an `attrpath` in a `source` file.

    # Arguments

    - `source` (path or string)

      Path to the Nix file declaring the derivation to wrap.
      The expression in the file must be function that takes an attribute set where all values have defaults.

      If the path points to a directory, the complete directory this file lives in will be copied into the store.
      The Nix expression must not access files outside of this directory.

      If the path points to a single file, the Nix experession in the file must not refer to other files.

      The most robust approach is using a file from a [file set](https://nixos.org/manual/nixpkgs/stable/#sec-functions-library-fileset).

    - `attrpath` (list of strings)

      The [attribute path](https://nix.dev/manual/nix/2.19/language/operators#attribute-selection) to the derivation in the expression at `source` to wrap, denoted as a list of path components.

    - `nix` (derivation or string, optional)

      Path to a Nix package that has `nix-build`.
      If not set, `nix-build` is used directly.

    - `nix-build-args` (list of strings, optional)

      Default: `[ ]`

      [Arguments](https://nix.dev/manual/nix/2.19/command-ref/nix-build#options) to pass to `nix-build` for the on-demand realisation.

    - `nix-build-env` (attribute set, optional)

      Default: `{ }`

      [Environment variables](https://nix.dev/manual/nix/2.19/command-ref/nix-build#common-environment-variables) to set on the invocation of `nix-build` for the on-demand realisation.

    # Example

    ```nix
    nix-build {
      source = ${with fileset; toSource {
        root = ./.;
        fileset = unions [ ./default.nix ./npins ];
      }};
      attrpath = [ "foo" "bar" ];
      nix-build-env = { NIX_PATH=""; };
      nix-build-args = [ "--no-out-link" ];
    }
    ```

    ```console
    NIX_PATH= nix-build /nix/store/...-source -A foo.bar --no-out-link
    ```
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
    mapFileAttrsRecursiveCond lib.isDerivation lazificator source attrs;

  lazy-build =
    let
      build = nix-build: drv:
        writeShellApplication { inherit (drv) name; text = ''exec ${nix-build} "$@"''; };
    in
    lazify build;

  lazy-run =
    let
      run = nix-build: drv:
        writeShellApplication {
          name = drv.meta.mainProgram;
          text = ''exec "$(${nix-build} --no-out-link)"/bin/${drv.meta.mainProgram} "$@"'';
        };
    in
    lazify run;

  mapFileAttrsRecursiveCond = pred: f: path: attrs:
    with lib;
    mapAttrsRecursiveCond
      (value: !pred value)
      (attrpath: value: if ! lib.isAttrs value then value else f attrpath value)
      attrs;

  file-is-autocallable = context: path:
    with lib;
    if !pathExists path then
      throw "${context}: source file '${toString path}' does not exist"
    else if pathIsDirectory path && !pathExists "${path}/default.nix" then
      throw "${context}: source file '${toString path}/default.nix' does not exist"
    else if !isFunction (import path) then
      throw "${context}: expression in '${toString path}' must be a function but is a ${builtins.typeOf expression}"
    else
      all id (mapAttrsToList
        (name: value:
          if value then value else
          throw "${context}: function argument '${name}' in '${toString path}' must have a default value"
        )
        (__functionArgs (import path)));

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
