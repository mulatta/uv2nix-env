{
  lib,
  pkgs,
  cuda ? false,
}:
# Shared fixup applied by every overlay: autoPatchelf a prebuilt binary wheel
# (fix RPATHs), add the usual native libs, and — under CUDA — append the host
# driver's lib dir so libcuda.so resolves at runtime. Returns a function
# `drv: extraBuildInputs -> drv'`.
drv: extraBuildInputs:
drv.overrideAttrs (
  old:
  {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.autoPatchelfHook ];
    buildInputs =
      (old.buildInputs or [ ])
      ++ [
        pkgs.stdenv.cc.cc.lib
        pkgs.zlib
      ]
      ++ extraBuildInputs;
    # Sibling CUDA wheels / dlopen'd plugins resolve at runtime, not build time.
    autoPatchelfIgnoreMissingDeps = [ "*" ];
  }
  // lib.optionalAttrs cuda {
    appendRunpaths = [ "${pkgs.addDriverRunpath.driverLink}/lib" ];
  }
)
