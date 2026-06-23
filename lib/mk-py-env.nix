{
  lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
# mkPyEnv: turn a uv workspace (pyproject.toml + uv.lock) into a Nix virtual env,
# composing build-system fixups + the workspace overlay + the shared overrides +
# any project-specific overrides. This is the ~one function every project reuses.
let
  mkOverrides = import ./overrides.nix;
in
{
  pkgs,
  # Directory holding pyproject.toml and uv.lock.
  workspaceRoot,
  python ? pkgs.python312,
  # Enable CUDA driver runpath wiring for GPU wheels.
  cuda ? false,
  # "wheel" (fast, prebuilt) or "sdist" (build from source).
  sourcePreference ? "wheel",
  # Project-specific scope overrides applied last (final: prev: { ... }).
  overrides ? (_final: _prev: { }),
  name ? "venv",
}:
let
  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  workspaceOverlay = workspace.mkPyprojectOverlay { inherit sourcePreference; };

  pythonSet = (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope (
    lib.composeManyExtensions [
      pyproject-build-systems.overlays.default
      workspaceOverlay
      (mkOverrides { inherit lib pkgs cuda; })
      overrides
    ]
  );
in
pythonSet.mkVirtualEnv name workspace.deps.default
