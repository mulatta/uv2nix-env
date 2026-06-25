{
  lib,
  nixpkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
# mkWorkspace: load a uv workspace (pyproject.toml + uv.lock) once and return a
# first-class attrset of derived outputs that share one resolved package set:
#   { workspace; pythonSet; python; venv; devShell; }
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
  # { mypkg = [ "gpu" ]; }. Merged over the default closure. Use `mkVenv` (below)
  # to build further variants from the same loaded workspace.
  extras ? { },
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
        modules = concernModules;
      })
      overrides
    ]
  );

  # torch finds CUDA libs via RPATH, but JAX resolves them via LD_LIBRARY_PATH at
  # runtime. Under cuda, wrap python so the nvidia wheel lib dirs + host driver
  # are on the loader path. Harmless for torch (additive); no-op without cuda.
  wrapCuda =
    v:
    if !cuda then
      v
    else
      pkgs.symlinkJoin {
        inherit (v) name;
        paths = [ v ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          libdirs=""
          for d in ${v}/lib/python*/site-packages/nvidia/*/lib; do
            [ -d "$d" ] && libdirs="$libdirs''${libdirs:+:}$d"
          done
          driver="${pkgs.addDriverRunpath.driverLink}/lib"
          for py in python python3; do
            if [ -e "$out/bin/$py" ]; then
              rm -f "$out/bin/$py"
              makeWrapper "${v}/bin/$py" "$out/bin/$py" \
                --prefix LD_LIBRARY_PATH : "$libdirs:$driver"
            fi
          done
        '';
      };

  # Editable dev set: source is loaded from $REPO_ROOT at runtime (impure).
  editableSet = pythonSet.overrideScope (
    workspace.mkEditablePyprojectOverlay { root = "$REPO_ROOT"; }
  );

  # A bare extras list targets the workspace's root package; an attrset
  # ({ pkg = [ ... ]; }) targets packages explicitly (multi-member workspaces).
  rootName = builtins.head (builtins.attrNames workspace.deps.default);
  toSpec = e: if builtins.isAttrs e then e else { ${rootName} = e; };

  # Build a venv from this one resolved set. `extras` selects optional
  # dependencies (a list for the root package, or an attrset per package) merged
  # over the default closure; `editable` swaps in the $REPO_ROOT set. CUDA
  # wrapping is applied, so a project can build several variants without
  # reloading the workspace.
  mkVenv =
    args:
    let
      venvName = args.name or name;
      venvExtras = toSpec (args.extras or extras);
      editable = args.editable or false;
    in
    wrapCuda (
      (if editable then editableSet else pythonSet).mkVirtualEnv venvName (
        workspace.deps.default // venvExtras
      )
    );

  # Build many named venvs at once: { <name> = <extras>; } -> { <name> = <venv>; }.
  venvs = builtins.mapAttrs (
    venvName: venvExtras:
    mkVenv {
      name = venvName;
      extras = venvExtras;
    }
  );

  venv = mkVenv { };
  devVenv = wrapCuda (editableSet.mkVirtualEnv "${name}-dev" workspace.deps.all);
  devShell = pkgs.mkShell {
    packages = [
      devVenv
      pkgs.uv
    ];
    env = {
      UV_NO_SYNC = "1";
      UV_PYTHON = "${devVenv}/bin/python";
      UV_PYTHON_DOWNLOADS = "never";
    };
    shellHook = ''
      unset PYTHONPATH
      export REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    '';
  };
in
{
  inherit
    workspace
    pythonSet
    python
    venv
    mkVenv
    venvs
    devShell
    ;
}
