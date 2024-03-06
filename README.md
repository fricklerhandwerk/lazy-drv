# `lazy-run`

Build executables from Nix derivations on demand.

## Motivation

Nix does not allow on-demand [realisation](https://nix.dev/manual/nix/2.19/glossary#gloss-realise) of store paths.
But sometimes it would be nice to have a large closure only realised when it's actually accessed, for example when a rarely-used helper command is run.

This tool is inspired by [TVL's `lazy-deps`](https://cs.tvl.fyi/depot@0c0edd5928d48c9673dd185cd332f921e64135e7/-/blob/nix/lazy-deps/default.nix?).

It trades saving initial build time against adding a startup time overhead.
And it meshes well with [`attr-cmd`](https://github.com/fricklerhandwerk/attr-cmd), a library for producing command line programs from attribute sets.

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
  example = pkgs.writeShellScriptBin "example-executable" "echo I am lazy";
  lazy = with pkgs.lib; lazy-run {
    source = "${with fileset; toSource {
      root = ./.;
      fileset = unions [ ./default.nix ./npins ];
    }}";
    attrs = { example = { example-alias = "example-executable"; } };
  };
in
{
  inherit example;
  shell = pkgs.mkShellNoCC {
    packages = [
      lazy.example
      pkgs.npins
    ];
  };
}
```

```console
$ nix-shell -p npins --run "npins init"
$ nix-shell -A shell
[nix-shell:~]$ example-alias
this derivation will be built:
  /nix/store/...-example.drv
building '/nix/store/...-example-alias.drv'...
I am lazy
```

## Usage

`lazy-run` takes as argument an attribute set:

- `source` (path or string)

  Path to the Nix file declaring the derivation to wrap.
  The expression in the file must be function that takes an attribute set where all values have defaults.
  
  If the path points to a directory, the complete directory this file lives in will be copied into the store.
  The Nix expression must not access files outside of this directory.

  If the path points to a single file, the Nix experession in the file must not refer to other files.

  The most robust approach is using a file from a  [file set](https://nixos.org/manual/nixpkgs/stable/#sec-functions-library-fileset).

- `attrs` (attribute set)

  Nested attribute set denoting [attribute paths](https://nix.dev/manual/nix/2.19/language/operators#attribute-selection) to derivations in the expression cat `source` to wrap.
  Each leaf attribute set denotes aliases:
  Names of executables to make accessible through the wrapper are mapped to executables from the referenced derivation.
  If the leaf attribute set is empty, `meta.mainProgram` of the derivation is mapped to an executable of the same name.

  Leaf attributes which are not attribute sets are not changed.

- `nix` (derivation, optional)

  The Nix to use for building the wrapped derivation.

  The `nix-build` found in `$PATH` is used by default.
  This is the safest thing to do, as otherwise one may run into compatibility issues between different versions of the [Nix database](https://nix.dev/manual/nix/2.19/glossary#gloss-nix-database).

- `nix-build-args` (list of strings, optional)

  Default: `[ ]`

  [Arguments](https://nix.dev/manual/nix/2.19/command-ref/nix-build#options) to pass to `nix-build` for the on-demand realisation.

- `nix-build-env` (attribute set, optional)

  Default: `{ }`

  [Environment variables](https://nix.dev/manual/nix/2.19/command-ref/nix-build#common-environment-variables) to set on the invocation of `nix-build` for the on-demand realisation.

It returns an attribute set with the same structure as `attrs`.
Its leaves are derivations that produce executables with the names as specified in the leaves of the `attrs` parameter.
Calling such an executable will invoke `nix-build` to realise the actual executable provided by the wrapped derivation.

> **Note**
>
> There is of course a performance penalty at start-up of such an executable, which is traded for a saving of build time for the environment it's supposed to be used in.

## Future work

Obviously this is just a cheap trick that can't do more than run selected commands from derivations.

More fancy things, such as lazily exposing `man` pages or other auxiliary data from a package, would probably require integration into a configuration management framework like NixOS, since every tool in question would have to play along.

This could indeed be quite powerful:
Imagine wiring up `man` to accept an additional option `--nixpkgs`.
It would then first inspect `$MANPATH`, and on failure leverage [`nix-index`](https://github.com/nix-community/nix-index) to realise the appropriate derivation on the fly.
