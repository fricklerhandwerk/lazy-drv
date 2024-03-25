# `lazy-drv`

Build executables from Nix derivations on demand.

## Motivation

Nix does not allow on-demand [realisation](https://nix.dev/manual/nix/2.19/glossary#gloss-realise) of store paths.
But sometimes it would be nice to have a large closure only realised when it's actually accessed, for example when a rarely-used helper command is run.

This tool is inspired by [TVL's `lazy-deps`](https://cs.tvl.fyi/depot@0c0edd5928d48c9673dd185cd332f921e64135e7/-/blob/nix/lazy-deps/default.nix).

It trades saving initial build time against adding a startup time overhead.
And it meshes well with [`attr-cmd`](https://github.com/fricklerhandwerk/attr-cmd), a library for producing command line programs from attribute sets.

## Example

```nix
# default.nix
let
  pkgs = import <nixpkgs> {};
  lazy-drv = pkgs.callPackage <lazy-drv> {};

  example = pkgs.writeShellScriptBin "example-command" "echo I am lazy";

  lazy = lazy-drv.lib.lazy-run {
    source = "${with pkgs.lib.fileset; toSource {
      root = ./.;
      fileset = unions [ ./default.nix ];
    }}";
    attrs = { inherit example; };
    nix-build-args = [ "--no-out-link" ];
  };
in
{
  inherit example;
  shell = pkgs.mkShellNoCC {
    packages = with lib; collect isDerivation lazy;
  };
}
```

```console
$ nix-shell -A shell -I lazy-drv=https://github.com/fricklerhandwerk/lazy-drv/tarball/master
[nix-shell:~]$ example-command
this derivation will be built:
  /nix/store/...-example-command.drv
building '/nix/store/...-example-command.drv'...
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

  The most robust approach is specifying source files with [file set library](https://nixos.org/manual/nixpkgs/stable/#sec-functions-library-fileset).

- `attrs` (attribute set)

  Nested attribute set of derivations.
  It must correspond to a top-level attribute set in the expression at `source`.


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
Its leaves are derivations that each produce an executable named after the `meta.mainProgram` attribute of the original derivation in `attrs`.
Calling such an executable will invoke `nix-build` to realise and run the actual executable provided by the wrapped derivation.
Leaf attributes which are not derivations are not changed.

> **Note**
>
> There is of course a performance penalty at start-up of such an executable, which is traded for a saving of build time for the environment it's supposed to be used in.

## Future work

Obviously this is just a cheap trick that can't do more than run selected commands from derivations.

More fancy things, such as lazily exposing `man` pages or other auxiliary data from a package, would probably require integration into a configuration management framework like NixOS, since every tool in question would have to play along.

This could indeed be quite powerful:
Imagine wiring up `man` to accept an additional option `--nixpkgs`.
It would then first inspect `$MANPATH`, and on failure leverage [`nix-index`](https://github.com/nix-community/nix-index) to realise the appropriate derivation on the fly.
