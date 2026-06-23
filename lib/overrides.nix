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

  # Wheels that ship prebuilt ELF and need RPATH fixing: every CUDA runtime wheel
  # (nvidia-*, whose suffix varies by CUDA version — -cu12 / -cu13 / none) plus
  # the frameworks. Prefix-matching is robust to those renames; over-matching a
  # pure wheel is a harmless no-op. Extend `frameworks` per your stack.
  frameworks = [
    "numpy"
    "scipy"
    "torch"
    "torchvision"
    "torchaudio"
    "jax"
    "jaxlib"
  ];

  # nvidia-* : CUDA runtime wheels (torch & jax share these)
  # jax-cuda*: jax's CUDA plugin/pjrt wheels (jax-cuda12-plugin, jax-cuda13-pjrt, …)
  isTarget = n: lib.hasPrefix "nvidia-" n || lib.hasPrefix "jax-cuda" n || builtins.elem n frameworks;
  present = builtins.filter isTarget (builtins.attrNames prev);
in
lib.genAttrs present (n: patch prev.${n} [ ])
