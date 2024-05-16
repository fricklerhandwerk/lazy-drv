{
  sources ? import ./nix/sources,
  system ? builtins.currentSystem,
  pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
  # a newer version of Nixpkgs ships with an improved rnix-parser,
  # but nixdoc upstream does not expose the package recipe...
  # https://github.com/nix-community/nixdoc/pull/125
  nixdoc ? pkgs.callPackage ./nix/nixdoc.nix { inherit sources; },
  git-hooks ? import sources.git-hooks { inherit pkgs system; },
}:
let
  update-readme = pkgs.callPackage ./nix/nixdoc-to-github.nix { inherit nixdoc; } {
    category = "lazy-drv";
    description = "\\`lazy-drv\\`";
    file = "${toString ./lib.nix}";
    output = "${toString ./README.md}";
  };
  inherit (git-hooks) lib;
  # wrapper to account for the custom lockfile location
  npins = pkgs.callPackage ./nix/npins.nix { };
in
{
  lib.lazy-drv = pkgs.callPackage ./lib.nix { };

  shell = pkgs.mkShellNoCC {
    packages = [
      npins
      nixdoc
    ];
    shellHook = ''
      ${with lib.git-hooks; pre-commit (wrap.abort-on-change update-readme)}
    '';
  };
}
