{ sources ? import ./npins
, system ? builtins.currentSystem
,
}:
let
  pkgs = import sources.nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };
  inherit (pkgs.callPackage ./lib.nix { }) lazy-run;
  scripts = {
    foo = pkgs.writeShellScriptBin "foo-executable" "echo this is lazy $@";
    bar = pkgs.writeShellScriptBin "bar-executable" "echo very lazy";
  };
  lazy = with pkgs.lib; lazy-run {
    source = "${with fileset; toSource {
      root = ./.;
      fileset = unions [ ./test.nix ./npins ./lib.nix ];
    }}/test.nix";
    attrs = {
      scripts = mapAttrs
        (name: value: { "${name}-alias" = "${name}-executable"; })
        scripts;
    };
  };
in
{
  inherit scripts;
  shell = with pkgs; mkShellNoCC {
    packages = lib.attrValues lazy.scripts ++ [
      npins
    ];
  };
}
