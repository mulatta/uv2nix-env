{
  lib,
  pkgs,
}:
# The venv/devShell builders over one already-resolved package set. mkWorkspace
# builds `pythonSet`/`editableSet`/`wrapCuda` and hands them here; keeping the
# builders out of mkWorkspace keeps each piece small and independently readable.
{
  workspace,
  pythonSet,
  editableSet,
  wrapCuda,
  name,
  extras,
}:
let
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
    mkVenv
    venvs
    venv
    mkDevShell
    devShell
    ;
}
