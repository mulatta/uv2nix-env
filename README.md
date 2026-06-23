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

- `lib.mkWorkspace` — load a uv workspace once; returns
  `{ workspace; pythonSet; python; venv; devShell; }` (one resolved set shared by
  all outputs). `venv` is the **pure** locked env; `devShell` is the **editable**
  interactive shell (impure — uses `$REPO_ROOT`).
- `lib.mkPyEnv` = `args: (mkWorkspace args).venv` — convenience for the venv.
- `lib.mkDevShell` = `args: (mkWorkspace args).devShell` — convenience for the shell.
- `lib.overlays.{cuda,torch,jax,wheels}` — the raw per-concern fixup overlays
  (each `{ lib, pkgs, cuda } -> final: prev:`) for manual composition.

All builders accept either `pkgs` or `system` (with `system`, `pkgs` is built
from this flake's nixpkgs with `allowUnfree`). So a project needs **only the
`py-overrides` input** — `uv2nix`/`pyproject-nix`/`pyproject-build-systems` are
inherited transitively.

## Usage in a project

```nix
# <project>/flake.nix
{
  inputs.py-overrides.url = "github:mulatta/bioinformatics-py-overrides";

  outputs =
    { py-overrides, ... }:
    let
      ws = py-overrides.lib.mkWorkspace {
        system = "x86_64-linux";
        workspaceRoot = ./.; # pyproject.toml + uv.lock
        cuda = true;
        # project-specific long-tail patches, if any:
        overrides = _final: _prev: { };
      };
    in
    {
      packages.x86_64-linux.default = ws.venv; # pure, run/package
      devShells.x86_64-linux.default = ws.devShell; # editable dev
    };
}
```

Each project keeps only its `uv.lock` and a thin flake; the heavy wheel/CUDA
fixups are inherited from here.

> Editable dev shells (`devShell`) need a build backend that supports editable
> installs natively — **`uv_build`** is recommended (hatchling additionally needs
> the `editables` build dep). The pure `venv` works with any backend.

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
