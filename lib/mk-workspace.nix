{
  lib,
  nixpkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
# mkWorkspace: load a uv workspace (pyproject.toml + uv.lock) once and return a
# first-class attrset of derived outputs that share one resolved package set:
#   { workspace; pythonSet; python; venv; mkVenv; venvs; devShell; mkDevShell; }
# - venv     : PURE, hash-locked virtual env (build / run / package).
# - devShell : editable interactive shell (impure — references $REPO_ROOT live),
#              mirroring uv2nix's own hello-world template split.
# mkPyEnv / mkDevShell (flake.nix) are thin aliases onto .venv / .devShell.
let
  # Per-concern rule modules ({ matches; patch; }); applied as one overlay
  # (single attrNames pass) by lib/apply-concerns.nix.
  concernModules = [
    ../overlays/wheels.nix
    ../overlays/cuda.nix
    ../overlays/torch.nix
    ../overlays/pyg.nix
    ../overlays/jax.nix
    ../overlays/rapids.nix
  ];
in
{
  # Provide `pkgs` directly, or `system` to build it from this flake's nixpkgs
  # (allowUnfree on for CUDA). Passing `pkgs` lets a project share its own
  # nixpkgs (ideally `follows = "uv2nix-env/nixpkgs"` to stay consistent).
  system ? null,
  pkgs ? import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  },
  workspaceRoot,
  python ? pkgs.python312,
  cuda ? false,
  sourcePreference ? "wheel",
  overrides ? (_final: _prev: { }),
  name ? "venv",
  # Optional-dependencies for the default `venv`, per package — e.g.
  # { mypkg = [ "gpu" ]; }. Combined with the default closure by a shallow (`//`)
  # merge: a package present in both takes the `extras` value, so listing a
  # package REPLACES its default extras rather than unioning (give the full list
  # if you mean to keep them). Use `mkVenv` (below) for further variants.
  extras ? { },
  # Project-specific concern modules, applied after the built-in ones. Each is
  # the same `{ lib, pkgs, cuda } -> { matches; patch; }` shape as lib.concerns.*
  # (a path or an inline function) — so a project patches a whole name *pattern*
  # (e.g. its 20 internal `acme-*` wheels) without forking. For a single package,
  # prefer `overrides`.
  extraConcerns ? [ ],
}:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  workspaceOverlay = workspace.mkPyprojectOverlay { inherit sourcePreference; };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.default
      workspaceOverlay
      (import ../lib/apply-concerns.nix {
        inherit lib pkgs cuda;
        modules = concernModules ++ extraConcerns;
      })
      overrides
    ]
  );

  # Editable dev set: source is loaded from $REPO_ROOT at runtime (impure).
  editableSet = pythonSet.overrideScope (
    workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; }
  );

  wrapCuda = import ./wrap-cuda.nix { inherit pkgs cuda; };

  # The venv/devShell builders over this resolved set (see lib/builders.nix).
  builders = import ./builders.nix { inherit lib pkgs; } {
    inherit
      workspace
      pythonSet
      editableSet
      wrapCuda
      name
      extras
      ;
  };
in
{
  inherit workspace pythonSet python;
  inherit (builders)
    venv
    mkVenv
    venvs
    devShell
    mkDevShell
    ;
}
