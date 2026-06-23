{
  lib,
  pkgs,
  cuda ? false,
}:
# Shared pyproject (uv2nix) overrides. uv resolves *versions* per project from
# uv.lock; what is reusable across projects is the *fixup logic* for wheels that
# ship prebuilt ELF binaries (RPATHs, libstdc++/zlib, CUDA driver) — encoded
# here once. This is a scope overlay (final: prev:) over the python package set.
_final: prev:
let
  # Patch a binary wheel: fix RPATHs via autoPatchelf, add the usual native
  # libs, and (under CUDA) let the loader reach the host driver's libcuda.so.
  patch =
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
        # Sibling CUDA wheels / dlopen'd plugins are resolved at runtime, not now.
        autoPatchelfIgnoreMissingDeps = [ "*" ];
      }
      // lib.optionalAttrs cuda {
        # NixOS exposes the GPU driver (libcuda.so) here; torch needs it at runtime.
        appendRunpaths = [ "${pkgs.addDriverRunpath.driverLink}/lib" ];
      }
    );

  # Binary wheels that commonly need RPATH fixing. Extend per the ML stack you
  # use; over-listing a pure wheel is harmless (autoPatchelf is then a no-op).
  binaryWheels = [
    "numpy"
    "torch"
    "torchvision"
    "torchaudio"
    "jax"
    "jaxlib"
    "nvidia-cublas-cu12"
    "nvidia-cuda-cupti-cu12"
    "nvidia-cuda-nvrtc-cu12"
    "nvidia-cuda-runtime-cu12"
    "nvidia-cudnn-cu12"
    "nvidia-cufft-cu12"
    "nvidia-curand-cu12"
    "nvidia-cusolver-cu12"
    "nvidia-cusparse-cu12"
    "nvidia-nccl-cu12"
    "nvidia-nvjitlink-cu12"
    "nvidia-nvtx-cu12"
  ];

  present = builtins.filter (n: builtins.hasAttr n prev) binaryWheels;
in
lib.genAttrs present (n: patch prev.${n} [ ])
