{
  lib,
  pkgs,
  cuda ? false,
  cudaIgnoredMissingDeps ? [ "*" ],
}:
# Augment a uv2nix-built wheel. uv2nix already adds autoPatchelfHook and
# manylinux policy libs; this adds libstdc++/zlib for non-manylinux wheels plus
# any explicit extra inputs. CUDA mode adds the host driver's libcuda.so runpath;
# projects may narrow or disable ignored missing deps with cudaIgnoredMissingDeps.
drv: extraBuildInputs:
drv.overrideAttrs (
  old:
  {
    buildInputs =
      (old.buildInputs or [ ])
      ++ [
        pkgs.stdenv.cc.cc.lib
        pkgs.zlib
      ]
      ++ extraBuildInputs;
  }
  // lib.optionalAttrs cuda {
    appendRunpaths = [ "${pkgs.addDriverRunpath.driverLink}/lib" ];
  }
  // lib.optionalAttrs (cuda && cudaIgnoredMissingDeps != [ ]) {
    autoPatchelfIgnoreMissingDeps = cudaIgnoredMissingDeps;
  }
)
