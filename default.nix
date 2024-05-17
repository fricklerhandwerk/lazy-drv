{
  sources ? import ./nix/sources,
  system ? builtins.currentSystem,
  pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; },
  nixdoc-to-github ? import sources.nixdoc-to-github { inherit pkgs system; },
  git-hooks ? import sources.git-hooks { inherit pkgs system; },
}:
let
  lib  = {
    inherit (git-hooks.lib) git-hooks;
    inherit (nixdoc-to-github.lib) nixdoc-to-github;
  };
  update-readme = lib.nixdoc-to-github.run {
    category = "lazy-drv";
    description = "\\`lazy-drv\\`";
    file = "${toString ./lib.nix}";
    output = "${toString ./README.md}";
  };
  # wrapper to account for the custom lockfile location
  npins = pkgs.callPackage ./nix/npins.nix { };
in
{
  lib.lazy-drv = pkgs.callPackage ./lib.nix { };

  shell = pkgs.mkShellNoCC {
    packages = [
      npins
    ];
    shellHook = ''
      ${with lib.git-hooks; pre-commit (wrap.abort-on-change update-readme)}
    '';
  };
}
