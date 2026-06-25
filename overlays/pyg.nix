{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch Geometric C-extension wheels (torch-scatter/-sparse/-cluster/
# -spline-conv/pyg-lib). Linked against libtorch + CUDA runtime; those deps stay
# unresolved at build time since `import torch` loads them into the process first.
#
# These wheels come from PyG's flat index (data.pyg.org), which publishes no
# hashes — a *lockfile* concern, not a build one: the consumer must complete the
# missing sha256 in their uv.lock (uv preserves manually-provided hashes).
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match =
    n:
    builtins.elem n [
      "torch-scatter"
      "torch-sparse"
      "torch-cluster"
      "torch-spline-conv"
      "pyg-lib"
    ];
}
