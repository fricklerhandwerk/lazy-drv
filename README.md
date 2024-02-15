# `lazy-run`

Build executables from Nix derivations on demand.

## Motivation

Nix does not allow on-demand [realisation](https://nix.dev/manual/nix/2.19/glossary#gloss-realise) of store paths.
But sometimes it would be nice to have a large closure only realised when it's actually accessed, for example when a rarely-used helper command is run.

This tool is inspired by [TVL's `lazy-deps`](https://cs.tvl.fyi/depot@0c0edd5928d48c9673dd185cd332f921e64135e7/-/blob/nix/lazy-deps/default.nix?).

## Usage

`lazy-run` takes two arguments:

1. Attribute set with configuration parameters:

   - `nix` (Derivation, optional)

     The Nix to use for building the wrapped derivation.

     The `nix-build` found in `$PATH` is used by default.
     This is the safest thing to do, as otherwise one may run into compatibility issues between different versions of the [Nix database](https://nix.dev/manual/nix/2.19/glossary#gloss-nix-database).

   - `aliases` (Attribute set, optional)

     Default: `{ }`

     Names of executables to make accessible through the wrapper mapped to names of executables from the given derivation .

     By default, the value of `meta.mainProgram` is mapped to itself.

2. Derivation to wrap

It returns a derivation which produces small executables with the names from the `aliases` parameter.
Calling such an executable will run the `nix-build` to realise the actual executable provided by the wrapped derivation and run it.

> **Note**
>
> There is of course a performance penalty at start-up of such an executable, which is traded for a saving of build time for the environment it's supposed to be used in.

## Example

```nix
# ./default.nix
{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
let
  pkgs = import sources.nixpkgs {
    inherit system;
    config = { };
    overlays = [ ];
  };
  inherit (pkgs.callPackage "${sources.lazy-run}/lib.nix" {}) lazy-run;
  script = pkgs.writeScriptBin "example" "echo I'm lazy";
  lazy = lazy-run {} script;
in
rec {
  shell = pkgs.mkShellNoCC {
    packages = [
      lazy
      pkgs.npins
    ];
  };
}
```

```console
$ nix-shell -p npins --run "npins init"
$ nix-shell
[nix-shell:~]$ example
this derivation will be built:
  /nix/store/...-example.drv
building '/nix/store/...-example.drv'...
I'm lazy
```
