{
  pkgs,
  cuda ? false,
}:
# torch finds CUDA libs via RPATH, but JAX resolves them via LD_LIBRARY_PATH at
# runtime. Under cuda, wrap python so the nvidia wheel lib dirs + host driver are
# on the loader path (additive/harmless for torch). No-op without cuda.
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
  }
