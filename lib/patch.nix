{
  lib,
  pkgs,
  cuda ? false,
}:
# Augment a uv2nix-built wheel. uv2nix already adds autoPatchelfHook and
# manylinux policy libs; this adds libstdc++/zlib for non-manylinux wheels plus
# any explicit extra inputs. CUDA mode is lenient for sibling nvidia-* wheels and
# adds the host driver's libcuda.so runpath; CPU mode stays strict.
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
    autoPatchelfIgnoreMissingDeps = [ "*" ];
    appendRunpaths = [ "${pkgs.addDriverRunpath.driverLink}/lib" ];
  }
)
