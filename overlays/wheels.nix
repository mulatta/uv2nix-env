{
  lib,
  pkgs,
  cuda ? false,
}:
# Generic prebuilt binary wheels (not tied to a framework) that bundle ELF and
# sometimes need extra system libs. `specs` maps package -> extra buildInputs.
let
  cu = pkgs.cudaPackages;
  specs = {
    numpy = [ ];
    scipy = [ ];
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
  };
in
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match = n: builtins.hasAttr n specs;
  extraInputs = name: specs.${name};
}
