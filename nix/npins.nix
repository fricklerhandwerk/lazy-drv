{ lib, runCommand, makeWrapper, npins }:
runCommand "npins" { buildInputs = [ makeWrapper ]; } ''
  mkdir -p $out/bin
  cp ${npins}/bin/* $out/bin/
  wrapProgram $out/bin/npins --add-flags "-d ${toString ./sources}"
''
