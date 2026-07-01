{
  lib,
  pkgs,
}:
# venv/devShell builders over one already-resolved package set, fed by mkWorkspace.
{
  workspace,
  pythonSet,
  editableSet,
  wrapCuda,
  name,
  extras,
  mainProgram,
}:
let
  # A bare extras list targets the workspace's root package; an attrset
  # ({ pkg = [ ... ]; }) targets packages explicitly (multi-member workspaces).
  rootName = builtins.head (builtins.attrNames workspace.deps.default);
  toSpec = e: if builtins.isAttrs e then e else { ${rootName} = e; };

  withMainProgram =
    program: drv:
    if program == null then
      drv
    else
      drv.overrideAttrs (old: {
        meta = (old.meta or { }) // {
          mainProgram = program;
        };
      });

  # `extras` (list for root pkg, or attrset per pkg) is `//`-merged over the
  # default closure, so a listed package's extras REPLACE its defaults, not union.
  # `editable` swaps in the $REPO_ROOT set. `mainProgram` sets meta.mainProgram
  # for `nix run .#pkg`.
  mkVenv =
    args:
    let
      venvName = args.name or name;
      venvExtras = toSpec (args.extras or (args.deps or extras));
      editable = args.editable or false;
      venvMainProgram = args.mainProgram or mainProgram;
    in
    withMainProgram venvMainProgram (
      wrapCuda (
        (if editable then editableSet else pythonSet).mkVirtualEnv venvName (
          workspace.deps.default // venvExtras
        )
      )
    );

  # { <name> = <extras>; } or
  # { <name> = { deps = …; extras = …; mainProgram = …; }; }.
  venvs = builtins.mapAttrs (
    venvName: venvSpec:
    mkVenv (
      if
        builtins.isAttrs venvSpec
        && (venvSpec ? deps || venvSpec ? extras || venvSpec ? editable || venvSpec ? mainProgram)
      then
        { name = venvName; } // venvSpec
      else
        {
          name = venvName;
          extras = venvSpec;
        }
    )
  );

  venv = mkVenv { };

  # `extras` like mkVenv; omit it for the full deps.all closure. `nativeLibs`
  # extends LD_LIBRARY_PATH (libstdc++ and zlib are always present, for the
  # C-extension wheels most stacks pull in). `env`/`shellHook`/`packages` merge
  # over the defaults.
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
