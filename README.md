# bioinformatics-py-overrides

Shared [uv2nix](https://github.com/pyproject-nix/uv2nix) overrides and an env
builder for GPU/ML Python stacks (torch, jax, …) used in bioinformatics
analysis.

This is **not** a package registry. uv resolves package *versions* per project
from each `uv.lock`; what is reusable is the *fixup logic* for prebuilt binary
wheels (RPATHs, libstdc++/zlib, CUDA driver wiring). That lives here once and is
composed into every project's env.

Companion to [`bioinformatics-toolkits`](../bioinformatics-toolkits), which holds
CLI tools (foldseek, gemme, …). Rule of thumb:

- **`import` it in analysis code** → here / uv2nix (esm, torch, biotite, …)
- **run it as a command** → bioinformatics-toolkits (foldseek, gemme, …)

## Public API

- `lib.mkPyEnv` — build a virtual env from a uv workspace (composes all overlays
  below + the CUDA/JAX runtime wiring).
- `lib.overlays.{cuda,torch,jax,wheels}` — the raw per-concern fixup overlays
  (each `{ lib, pkgs, cuda } -> final: prev:`) for manual composition.

## Usage in a project

```nix
# <project>/flake.nix
{
  inputs.py-overrides.url = "github:mulatta/bioinformatics-py-overrides";
  inputs.nixpkgs.follows = "py-overrides/nixpkgs";

  outputs =
    { nixpkgs, py-overrides, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true; # for CUDA
      };
      env = py-overrides.lib.mkPyEnv {
        inherit pkgs;
        workspaceRoot = ./.; # pyproject.toml + uv.lock
        cuda = true;
        # project-specific long-tail patches, if any:
        overrides = _final: _prev: { };
      };
    in
    {
      devShells.${system}.default = pkgs.mkShellNoCC { packages = [ env ]; };
    };
}
```

Each project keeps only its `uv.lock` and a thin flake; the heavy wheel/CUDA
fixups are inherited from here.

## Extending the overrides

Fixups are split by concern under `overlays/` (each composed by `mkPyEnv`):

- `cuda.nix` — `nvidia-*` CUDA runtime wheels (shared GPU base)
- `torch.nix` — PyTorch ecosystem
- `jax.nix` — JAX + its `jax-cuda*` plugin wheels
- `wheels.nix` — generic binary wheels (numpy/scipy)

`lib/patch.nix` is the shared autoPatchelf + driver-runpath helper. To support a
new stack (e.g. RAPIDS), add an `overlays/<name>.nix` and list it in
`lib/mk-py-env.nix`. Over-matching a pure wheel is a harmless no-op. Note these
fixups are generic ML/CUDA — not bioinformatics-specific; bio-only patches would
go in a future `overlays/bio.nix`.

## Self-check

`example/` is a tiny workspace built by `checks.example` / `packages.example` to
verify the wiring end-to-end. It depends on **numpy** (a binary wheel) so the
build actually exercises the autoPatchelf override path, while staying CPU-only:

```bash
nix flake check
nix build .#example && ./result/bin/python -c "import numpy; print('ok')"
```

Note: this does not exercise the CUDA/torch fixups (no GPU wheels); those are
validated by real projects that set `cuda = true`.
