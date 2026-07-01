{
  lib,
  nixpkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
# Load a uv workspace (pyproject.toml + uv.lock) once and return outputs sharing
# one resolved package set. venv is PURE/hash-locked; devShell is editable/impure
# (references $REPO_ROOT live), mirroring uv2nix's hello-world template split.
{
  # Pass `pkgs` to share a project's own nixpkgs (ideally follows uv2nix-env/nixpkgs),
  # or `system` to build it here with allowUnfree on for CUDA.
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
  # Optional-deps for the default venv, per package (e.g. { mypkg = [ "gpu" ]; }).
  # Shallow-merged (`//`) over the default closure: a listed package's extras
  # REPLACE its defaults, not union — give the full list to keep them.
  extras ? { },
  # Optional `meta.mainProgram` for the default venv, enabling `nix run .#pkg`.
  mainProgram ? null,
}:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  workspaceOverlay = workspace.mkPyprojectOverlay { inherit sourcePreference; };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.default
      workspaceOverlay
      # Universal wheel fixup (keyed off uv2nix's passthru.format), plus the
      # short exact-name table of per-package native libs. No name allowlist.
      (import ./base-overlay.nix {
        inherit lib pkgs cuda;
        extraInputs = import ./extra-inputs.nix { inherit pkgs; };
      })
      overrides
    ]
  );

  # Editable dev set: source loaded from $REPO_ROOT at runtime (impure).
  editableSet = pythonSet.overrideScope (
    workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; }
  );

  wrapCuda = import ./wrap-cuda.nix { inherit pkgs cuda; };

  builders = import ./builders.nix { inherit lib pkgs; } {
    inherit
      workspace
      pythonSet
      editableSet
      wrapCuda
      name
      extras
      mainProgram
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
