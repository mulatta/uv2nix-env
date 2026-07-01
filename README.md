# uv2nix-env

Shared [uv2nix](https://github.com/pyproject-nix/uv2nix) fixups and an env
builder for GPU/ML Python stacks (torch, jax, RAPIDS, …) — get a project's
Python env without hand-patching CUDA/native wheels.

This is **not** a package registry. uv resolves package *versions* per project
from each `uv.lock`; what is reusable is the *fixup logic* for prebuilt binary
wheels (RPATHs, libstdc++/zlib, CUDA driver wiring). That lives here once and is
composed into every project's env.

It's for any uv-based Python project that needs prebuilt GPU/native wheels. It
grew out of packaging bioinformatics stacks, but nothing here is domain-specific —
the fixups are about wheels and CUDA, not any one field. The dividing line it
draws is `import` vs. run:

- **`import` it in analysis code** → a Python env (esm, torch, biotite, …) — this
  is uv2nix-env's job.
- **run it as a command** → a standalone CLI tool (foldseek, gemme, …) — package
  that elsewhere (e.g. a dedicated tools flake); it doesn't belong in a uv env.

## Public API

- `lib.mkWorkspace` — load a uv workspace once; returns
  `{ workspace; pythonSet; python; venv; mkVenv; venvs; devShell; mkDevShell; }`
  (one resolved set shared by all outputs). `venv` is the **pure** locked env;
  `devShell` is the **editable** interactive shell (impure — uses `$REPO_ROOT`).
  Pass `extras` — a list for the root package (`[ "gpu" ]`) or an attrset
  (`{ pkg = [ "gpu" ]; }`) — to select optional-dependencies for `venv`. extras
  are `//`-merged over the default closure, so a listed package's extras
  **replace** its defaults (building `[ "esm" ]` drops a `test` group baked into
  the default closure; pass `[ "esm" "test" ]` to keep it). Pass
  `mainProgram` to set `meta.mainProgram` on the default `venv`.
- `ws.mkVenv { name ? …; extras ? …; editable ? false; mainProgram ? null; }` —
  build one further venv from the same loaded workspace. `mainProgram` sets
  `meta.mainProgram`, so package outputs can be run with `nix run .#pkg`.
- `ws.venvs { <name> = <extras>; … }` → `{ <name> = <venv>; … }` — build many
  named variants at once, for a project that ships several optional-dependency
  combinations from one `uv.lock`. Values may also be attrsets such as
  `{ deps = [ "gpu" ]; mainProgram = "my-cli"; }`; use `deps = { pkg = [ … ]; }`
  for multi-package workspaces to avoid ambiguity with variant options.
- `ws.mkDevShell { extras ? <all>; name ? …; env ? {}; shellHook ? ""; nativeLibs ? []; packages ? []; }`
  — an editable dev shell over selected extras (omit `extras` for the full
  closure, like `ws.devShell`). Standard uv/`REPO_ROOT` wiring and an
  LD_LIBRARY_PATH with libstdc++/zlib are built in; `env`/`shellHook`/`packages`
  merge over them, and `nativeLibs` extends the library path.
- `lib.mkPyEnv` = `args: (mkWorkspace args).venv` — convenience for the venv.
- `lib.mkDevShell` = `args: (mkWorkspace args).devShell` — convenience for the shell.
- `lib.mkPatch` — the shared per-wheel fixup (`{ lib, pkgs, cuda } -> drv ->
  extraBuildInputs -> drv'`). mkWorkspace already applies it to every wheel; reach
  for it inside a project's own `overrides` only when hand-patching a package.
- `lib.addBuildSystem` — the common `overrides` case (a package forgot its
  build-system): `overrides = final: prev: { fbpca = addBuildSystem final { setuptools = [ ]; } prev.fbpca; }`.

All builders accept either `pkgs` or `system` (with `system`, `pkgs` is built
from this flake's nixpkgs with `allowUnfree`). So a project needs **only the
`uv2nix-env` input** — `uv2nix`/`pyproject-nix`/`pyproject-build-systems` are
inherited transitively. CUDA builds default to lenient missing-dependency
handling for sibling NVIDIA wheels; pass `cudaIgnoredMissingDeps = [ ];` for
strict auto-patchelf, or a narrower list for project policy.

## Performance and API caveats

`mkWorkspace` is the expensive boundary: it loads `uv.lock`, builds the
`pyproject-nix` package set, and composes build-system, workspace, native-wheel,
and project override overlays. Call it once per project/system/python/CUDA tuple,
then derive variants with `ws.mkVenv` or `ws.venvs`; repeated `mkWorkspace` calls
repeat that evaluation work.

The thin helpers (`mkVenv`, `venvs`, `mainProgram`) add negligible evaluation
cost compared with constructing the package set. Use them freely to keep variants
sharing one resolved workspace.

`ws.devShell` intentionally defaults to the full `workspace.deps.all` closure.
For large projects, or projects with optional extras that are slow or broken to
build, prefer `ws.mkDevShell { extras = [ … ]; }` so the shell only includes the
extras you need.

In consumer flakes, make shared inputs follow the consumer's pins to avoid lock
or nixpkgs duplication, for example:

```nix
inputs.uv2nix-env.inputs.nixpkgs.follows = "nixpkgs";
inputs.uv2nix-env.inputs.treefmt-nix.follows = "treefmt-nix";
```

## Quick start (templates)

Scaffold a project (these also serve as worked per-stack examples):

```bash
nix flake init -t github:mulatta/uv2nix-env#default   # CPU (numpy)
nix flake init -t github:mulatta/uv2nix-env#torch     # PyTorch + CUDA
nix flake init -t github:mulatta/uv2nix-env#jax       # JAX + CUDA (+ dm-haiku)
nix flake init -t github:mulatta/uv2nix-env#rapids    # RAPIDS cudf + CUDA
```

Then `uv add <deps>` / `uv lock`, and `nix build` (venv), `nix run` (template
example CLI), or `nix develop` (editable devShell).

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
        mainProgram = "my-cli"; # optional; enables nix run .#default
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

## CUDA strictness and executable wrapping

With `cuda = true`, uv2nix-env wraps all executable files in the venv's `bin/`
directory with the CUDA wheel library directories and host driver path in
`LD_LIBRARY_PATH`. This covers direct `python` use and console scripts selected
with `mainProgram`.

CUDA mode also keeps historical lenient auto-patchelf behavior by default:

```nix
cudaIgnoredMissingDeps = [ "*" ];
```

Set it to `[ ]` to fail on every unresolved NEEDED entry, or to a narrower list
when a project knows exactly which CUDA/driver references are expected to resolve
at runtime.

## How the fixup works

uv2nix already builds every wheel with `autoPatchelfHook` and the manylinux
policy libs for its platform tag, and tags it `passthru.format = "wheel"`. So
there is **no name allowlist**: `lib/base-overlay.nix` keys off that format flag
and applies `lib/patch.nix` to *every* wheel — adding libstdc++/zlib (for wheels
not covered by a manylinux tag) and, under `cuda`, the host driver runpath plus
`autoPatchelfIgnoreMissingDeps` (sibling `nvidia-*` wheels resolve at runtime).
CPU builds stay strict so a genuinely missing dep fails loudly.

`lib/extra-inputs.nix` is the only per-package knowledge — a short exact-name
attrset of native libs autoPatchelf can't infer (e.g. `numba -> tbb`). Keep this
list small and broadly reusable. For a single project-specific package, use that
project's `overrides` (reference it by attr name) rather than extending this
table. `overrides` is not a uv2nix-env abstraction; it is the standard
uv2nix/pyproject-nix escape hatch passed through by `mkWorkspace`.

To support a new broadly useful native wheel gap, first check whether it is:

1. a missing build/runtime library that many projects will hit → add an
   exact-name entry to `lib/extra-inputs.nix`;
2. a package-specific build quirk → keep it in that project's `overrides`;
3. a standalone CLI/tool dependency → package it outside the Python env.

These fixups are generic wheel/CUDA mechanics — not bioinformatics-specific.

## Self-check

`example/` is a tiny workspace built by `checks.example` / `packages.example` to
verify the wiring end-to-end. It depends on **numpy** (a binary wheel) so the
build actually exercises the autoPatchelf override path, while staying CPU-only:

```bash
nix flake check
nix run .#example
```

Note: the self-check evaluates the CUDA templates, but does not build the full
CUDA/torch closures. GPU wheel builds remain validated by real projects that set
`cuda = true`.
