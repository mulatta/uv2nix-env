{
  lib,
  pkgs,
  cuda ? false,
}:
# RAPIDS ecosystem wheels (cudf/cugraph/rmm/raft/ucxx/kvikio + their lib*/pylib*
# split packages). Ship prebuilt ELF and depend on the shared nvidia-* CUDA
# runtime (cuda.nix); uv resolves the inter-package graph so autoPatchelf finds
# sibling .so via buildInputs.
let
  # RAPIDS-unique roots. Deliberately avoid bare generic words ("raft", "rmm",
  # "ucxx") that could match unrelated PyPI packages — require their lib*/pylib*/
  # -cu forms instead.
  prefixes = [
    "cudf"
    "libcudf"
    "pylibcudf"
    "librmm"
    "rmm-cu"
    "cugraph"
    "libcugraph"
    "pylibcugraph"
    "libraft"
    "pylibraft"
    "raft-dask"
    "ucxx-cu"
    "libucxx"
    "libucx"
    "kvikio"
    "libkvikio"
    "dask-cuda"
    "dask-cudf"
    "distributed-ucxx"
  ];
in
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match = n: lib.any (p: lib.hasPrefix p n) prefixes;
}
