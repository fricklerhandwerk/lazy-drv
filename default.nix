let
  sources = import ./npins;
in
{ pkgs ? import sources.nixpkgs { inherit system; config = { }; overlays = [ ]; }
, system ? builtins.currentSystem
}:
{
  lib = pkgs.callPackage ./lib.nix { };

  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
    ];
  };
}
