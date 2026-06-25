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
  # dependencies (a list for the root package, or an attrset per package);
  # `//`-merged over the default closure, so a listed package's extras REPLACE
  # its defaults (a variant built as `[ "esm" ]` drops a `test` group that lived
  # in the default closure — pass `[ "esm" "test" ]` to keep it). `editable`
  # swaps in the $REPO_ROOT set. CUDA wrapping is applied, so a project can build
  # several variants without reloading the workspace.
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

  # Editable dev shell over this resolved set. `extras` selects optional
  # dependencies (list/attrset like mkVenv); omit it for the full deps.all
  # closure. `nativeLibs` extends the editable shell's LD_LIBRARY_PATH (libstdc++
  # and zlib are always present, for the C-extension wheels most stacks pull in).
  # `env`/`shellHook`/`packages` are merged over the library defaults so a project
  # adds its own without restating the standard uv/REPO_ROOT wiring.
  mkDevShell =
    args:
    let
      shellName = args.name or "${name}-dev";
      shellDeps =
        if args ? extras then workspace.deps.default // toSpec args.extras else workspace.deps.all;
      dv = wrapCuda (editableSet.mkVirtualEnv shellName shellDeps);
      libraryPath = lib.makeLibraryPath (
        [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ]
        ++ (args.nativeLibs or [ ])
      );
    in
    pkgs.mkShell {
      packages = [
        dv
        pkgs.uv
      ]
      ++ (args.packages or [ ]);
      env = {
        UV_NO_SYNC = "1";
        UV_PYTHON = "${dv}/bin/python";
        UV_PYTHON_DOWNLOADS = "never";
        LD_LIBRARY_PATH = libraryPath;
      }
      // (args.env or { });
      shellHook = ''
        unset PYTHONPATH
        export REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
      ''
      + (args.shellHook or "");
    };

  devShell = mkDevShell { };
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
    mkDevShell
    ;
}
