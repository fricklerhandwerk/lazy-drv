let
  sources = import ./npins;
  nixdoc-package = { sources, lib, rustPlatform }:
    let
      src = sources.nixdoc;
      package = (lib.importTOML "${src}/Cargo.toml").package;
    in
    rustPlatform.buildRustPackage {
      pname = package.name;
      version = package.version;
      inherit src;
      cargoLock = {
        lockFile = "${src}/Cargo.lock";
      };
    };
in
{
  pkgs ? import sources.nixpkgs {
    inherit system;
    config = { };
    overlays = [ (final: prev: { inherit nixdoc; })];
  },
  nixdoc ? pkgs.callPackage nixdoc-package { inherit sources; },
  git-hooks ? import sources.git-hooks { inherit pkgs system; },
  system ? builtins.currentSystem,
}:
let
  update-readme = pkgs.writeShellApplication {
    name = "pre-commit-hook";
    runtimeInputs = with pkgs; [ git pkgs.nixdoc busybox perl ];
    text = ''
      nixdoc --category lazy-drv --description "\`lazy-drv\`" --file lib.nix | awk '
      BEGIN { p=0; }
      /^\:\:\:\{\.example\}/ { print "> **Example**"; p=1; next; }
      /^\:\:\:/ { p=0; next; }
      p { print "> " $0; next; }
      { print }
      ' | sed 's/[[:space:]]*$//' | sed 's/ {#[^}]*}//g' | \
          sed 's/function-library-//g' | perl -pe 's/\(#([^)]+)\)/"(#" . $1 =~ s|\.||gr . ")" /eg' > README.md
      {
        changed=$(git diff --name-only --exit-code);
        status=$?;
      } || true

      if [ $status -ne 0 ]; then
        echo Files updated by pre-commit hook:
        echo "$changed"
        exit $status
      fi
    '';
  };
  inherit (git-hooks) lib;
in
{
  lib.lazy-drv = pkgs.callPackage ./lib.nix { };

  shell = pkgs.mkShellNoCC {
    packages = [
      pkgs.npins
      pkgs.nixdoc
    ];
    shellHook = ''
      ${lib.git-hooks.pre-commit update-readme}
    '';
  };
}
