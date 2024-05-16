{ sources, lib, rustPlatform }:
let
  src = sources.nixdoc;
  package = (lib.importTOML "${src}/Cargo.toml").package;
in
rustPlatform.buildRustPackage {
  pname = package.name;
  version = package.version;
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";
}
