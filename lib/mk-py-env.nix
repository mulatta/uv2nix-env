{
  lib,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
# mkPyEnv: turn a uv workspace (pyproject.toml + uv.lock) into a Nix virtual env,
# composing build-system fixups + the workspace overlay + our per-concern fixup
# overlays + any project-specific overrides. This is the ~one function every
# project reuses.
let
  # Per-concern fixup overlays (see overlays/). Each is `{ lib; pkgs; cuda; } ->
  # final: prev: {…}` and touches a disjoint set of packages, so order is moot.
  concernOverlays = [
    ../overlays/wheels.nix
    ../overlays/cuda.nix
    ../overlays/torch.nix
    ../overlays/jax.nix
  ];
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
    lib.composeManyExtensions (
      [
        pyproject-build-systems.overlays.default
        workspaceOverlay
      ]
      ++ map (o: import o { inherit lib pkgs cuda; }) concernOverlays
      ++ [ overrides ]
    )
  );

  venv = pythonSet.mkVirtualEnv name workspace.deps.default;
in
# torch resolves its CUDA libs via RPATH (the overlays add the driver runpath),
# but JAX resolves them via LD_LIBRARY_PATH at runtime. Under cuda, wrap python so the
# nvidia wheel lib dirs + the host driver are on the loader path. Harmless for
# torch (additive). Non-CUDA envs are returned unwrapped.
if !cuda then
  venv
else
  pkgs.symlinkJoin {
    inherit name;
    paths = [ venv ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      libdirs=""
      for d in ${venv}/lib/python*/site-packages/nvidia/*/lib; do
        [ -d "$d" ] && libdirs="$libdirs''${libdirs:+:}$d"
      done
      driver="${pkgs.addDriverRunpath.driverLink}/lib"
      for py in python python3; do
        if [ -e "$out/bin/$py" ]; then
          rm -f "$out/bin/$py"
          makeWrapper "${venv}/bin/$py" "$out/bin/$py" \
            --prefix LD_LIBRARY_PATH : "$libdirs:$driver"
        fi
      done
    '';
  }
