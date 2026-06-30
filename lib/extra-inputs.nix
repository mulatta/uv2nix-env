{ pkgs }:
# Exact-name native libs that autoPatchelf cannot infer from NEEDED entries
# (for example, libraries loaded later via dlopen). Keep project-local quirks in
# that project's `overrides` instead.
let
  cu = pkgs.cudaPackages;
in
{
  # numba's TBB threading layer dlopens libtbb.so.12 (oneTBB).
  numba = [ (pkgs.tbb_2022_0 or pkgs.tbb) ];

  # cupy-cuda12x ships CUDA-linked .so but declares no nvidia-* deps (expects a
  # system CUDA), so feed it nixpkgs cudaPackages.
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
}
