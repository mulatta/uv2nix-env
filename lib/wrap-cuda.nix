{
  pkgs,
  cuda ? false,
}:
# torch finds CUDA libs via RPATH, but JAX resolves them via LD_LIBRARY_PATH at
# runtime. Under cuda, wrap venv executables so the nvidia wheel lib dirs + host
# driver are on the loader path (additive/harmless for torch). No-op without cuda.
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
      for d in ${v}/lib/python*/site-packages/nvidia/*/lib \
               ${v}/lib/python*/site-packages/cusparselt/lib; do
        [ -d "$d" ] && libdirs="$libdirs''${libdirs:+:}$d"
      done
      driver="${pkgs.addDriverRunpath.driverLink}/lib"
      for exe in "$out"/bin/*; do
        [ -e "$exe" ] || continue
        [ -f "$exe" ] || [ -L "$exe" ] || continue
        [ -x "$exe" ] || continue
        name="$(basename "$exe")"
        [ -e "${v}/bin/$name" ] || continue
        rm -f "$exe"
        makeWrapper "${v}/bin/$name" "$exe" \
          --prefix LD_LIBRARY_PATH : "$libdirs:$driver"
      done
    '';
  }
