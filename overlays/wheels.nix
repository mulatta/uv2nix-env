{
  lib,
  pkgs,
  cuda ? false,
}:
# Generic prebuilt binary wheels not tied to a framework, but which bundle ELF
# needing RPATH fixes and sometimes extra system libs. `specs` maps a package to
# its extra buildInputs (the shared patch also makes autoPatchelf non-fatal on
# the remainder). Extend as new stacks surface missing deps.
let
  patch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  cu = pkgs.cudaPackages;
  specs = {
    numpy = [ ];
    scipy = [ ];
    # numba's TBB threading layer dlopens libtbb.so.12 (oneTBB).
    numba = [ (pkgs.tbb_2022_0 or pkgs.tbb) ];
    # cupy-cuda12x ships CUDA-linked .so but does not declare the nvidia-* wheels
    # as deps (it expects a system CUDA), so feed it nixpkgs cudaPackages.
    cupy-cuda12x = [
      cu.libcublas
      cu.libcusolver
      cu.libcusparse
      cu.libcurand
      cu.libcufft
      cu.cuda_nvrtc
      cu.nccl
      cu.libcutensor
    ];
  };
in
_final: prev:
lib.genAttrs (builtins.filter (n: builtins.hasAttr n prev) (builtins.attrNames specs)) (
  n: patch prev.${n} specs.${n}
)
