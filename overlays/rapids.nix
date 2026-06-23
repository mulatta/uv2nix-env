{
  lib,
  pkgs,
  cuda ? false,
}:
# RAPIDS ecosystem wheels (cudf/cugraph/rmm/raft/ucxx/kvikio + their lib*/pylib*
# split packages). Like torch/jax these ship prebuilt ELF and depend on the
# shared nvidia-* CUDA runtime (handled by overlays/cuda.nix). uv resolves the
# inter-package graph (cudf -> libcudf -> librmm …) so autoPatchelf finds sibling
# .so via buildInputs. Start with the shared patch; widen per build errors.
let
  patch = drv: import ../lib/patch.nix { inherit lib pkgs cuda; } drv [ ];
  rapidsPrefixes = [
    "cudf"
    "libcudf"
    "pylibcudf"
    "rmm"
    "librmm"
    "cugraph"
    "libcugraph"
    "pylibcugraph"
    "raft"
    "libraft"
    "pylibraft"
    "raft-dask"
    "ucxx"
    "libucxx"
    "libucx"
    "kvikio"
    "libkvikio"
    "dask-cuda"
    "dask-cudf"
    "distributed-ucxx"
  ];
  isRapids = n: lib.any (p: lib.hasPrefix p n) rapidsPrefixes;
in
_final: prev: lib.genAttrs (builtins.filter isRapids (builtins.attrNames prev)) (n: patch prev.${n})
