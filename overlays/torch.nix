{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch ecosystem wheels. torch finds its CUDA libs via RPATH (the driver
# runpath from the shared patch under cuda is enough), so no runtime
# LD_LIBRARY_PATH wiring is needed.
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match =
    n:
    builtins.elem n [
      "torch"
      "torchvision"
      "torchaudio"
    ];
}
