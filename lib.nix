{ lib, symlinkJoin, writeShellApplication }:
rec {
  lazy-run =
    { source
    , attrs
    , nix ? null
    , nix-build-args ? [ ]
    , nix-build-env ? { }
    }:
    let
      lazyfy = attrpath: alias: name:
        let
          env = join " " (lib.mapAttrsToList (k: v: "${k}=${toString v}") nix-build-env);
          nix-build = attrpath: join " " (lib.filter (x: x != "") [
            env
            "nix-build ${source} -A ${join "." attrpath} --no-out-link"
            (join " " nix-build-args)
          ]);
        in
        writeShellApplication {
          name = alias;
          runtimeInputs = lib.optional (nix != null) nix;
          text = ''
            exec "$(${nix-build attrpath})"/bin/${name} "$@"
          '';
        };
      # from the derivation in `source` at `attrpath`, produce a list of derivations with one executable each.
      # the resulting executables map to original executables, as described by `aliases`.
      wrap = attrpath: aliases:
        with lib;
        let
          executables =
            if aliases != { } then aliases
            else {
              ${drv.meta.mainProgram} = "${drv.meta.mainProgram}";
            };
          drv =
            let
              error = throw "lazy-run: attribute path '${join "." attrpath}' does not exist in '${toString source}'";
            in
            attrByPath attrpath error (import source { });
        in
        symlinkJoin {
          name = "lazy-${drv.name}";
          paths = attrValues (mapAttrs
            (alias: name: lazyfy attrpath alias name)
            executables
          );
        };
    in
    with lib;
    mapAttrsRecursiveCond
      (attrs: !(all isString (attrValues attrs)))
      (attrpath: value: if ! isAttrs value then value else
      wrap attrpath value
      )
      attrs;

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
