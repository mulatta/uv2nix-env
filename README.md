# uv2nix-env

Shared [uv2nix](https://github.com/pyproject-nix/uv2nix) fixups and an env
builder for GPU/ML Python stacks (torch, jax, RAPIDS, …) — get a project's
Python env without hand-patching CUDA/native wheels.

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
  `{ workspace; pythonSet; python; venv; mkVenv; venvs; devShell; mkDevShell; }`
  (one resolved set shared by all outputs). `venv` is the **pure** locked env;
  `devShell` is the **editable** interactive shell (impure — uses `$REPO_ROOT`).
  Pass `extras` — a list for the root package (`[ "gpu" ]`) or an attrset
  (`{ pkg = [ "gpu" ]; }`) — to select optional-dependencies for `venv`.
- `ws.mkVenv { name ? …; extras ? …; editable ? false; }` — build one further
  venv from the same loaded workspace.
- `ws.venvs { <name> = <extras>; … }` → `{ <name> = <venv>; … }` — build many
  named variants at once, for a project that ships several optional-dependency
  combinations from one `uv.lock`.
- `ws.mkDevShell { extras ? <all>; name ? …; env ? {}; shellHook ? ""; nativeLibs ? []; packages ? []; }`
  — an editable dev shell over selected extras (omit `extras` for the full
  closure, like `ws.devShell`). Standard uv/`REPO_ROOT` wiring and an
  LD_LIBRARY_PATH with libstdc++/zlib are built in; `env`/`shellHook`/`packages`
  merge over them, and `nativeLibs` extends the library path.
- `lib.mkPyEnv` = `args: (mkWorkspace args).venv` — convenience for the venv.
- `lib.mkDevShell` = `args: (mkWorkspace args).devShell` — convenience for the shell.
- `lib.concerns.{cuda,torch,pyg,jax,rapids,wheels}` — the raw per-concern rule
  modules (each `{ lib, pkgs, cuda } -> { matches; patch; }`) that mkWorkspace
  composes into a single overlay.

All builders accept either `pkgs` or `system` (with `system`, `pkgs` is built
from this flake's nixpkgs with `allowUnfree`). So a project needs **only the
`uv2nix-env` input** — `uv2nix`/`pyproject-nix`/`pyproject-build-systems` are
inherited transitively.

## Quick start (templates)

Scaffold a project (these also serve as worked per-stack examples):

```bash
nix flake init -t github:mulatta/uv2nix-env#default   # CPU (numpy)
nix flake init -t github:mulatta/uv2nix-env#torch     # PyTorch + CUDA
nix flake init -t github:mulatta/uv2nix-env#jax       # JAX + CUDA (+ dm-haiku)
nix flake init -t github:mulatta/uv2nix-env#rapids    # RAPIDS cudf + CUDA
```

Then `uv add <deps>` / `uv lock`, and `nix build` (venv) or `nix develop`
(editable devShell).

## Usage in a project

```nix
# <project>/flake.nix
{
  inputs.uv2nix-env.url = "github:mulatta/uv2nix-env";

  outputs =
    { uv2nix-env, ... }:
    let
      ws = uv2nix-env.lib.mkWorkspace {
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

Fixups are split by concern under `overlays/`. Each file is a declarative rule
`{ lib, pkgs, cuda } -> { matches = name -> bool; patch = name -> drv -> drv'; }`;
`lib/apply-concerns.nix` composes them into one overlay (single `attrNames`
pass), and `lib/patch.nix` is the shared autoPatchelf + driver-runpath helper.

- `cuda.nix` — `nvidia-*` CUDA runtime wheels (shared GPU base)
- `torch.nix` — PyTorch ecosystem
- `pyg.nix` — PyTorch Geometric C-extensions (torch-scatter/-sparse/-cluster/-spline-conv/pyg-lib)
- `jax.nix` — JAX + its `jax-cuda*` plugin wheels
- `rapids.nix` — cudf/cugraph/rmm/raft/ucxx/kvikio family
- `wheels.nix` — generic binary wheels (numpy/scipy/numba/cupy), with per-package
  extra buildInputs

To support a new stack, add `overlays/<name>.nix` and list it in
`concernModules` (`lib/mk-workspace.nix`). Matchers are name-based — prefer
specific roots over bare generic words to avoid false positives (harmless no-ops,
but noise). These fixups are generic ML/CUDA — not bioinformatics-specific;
bio-only patches would go in a future `overlays/bio.nix`.

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
