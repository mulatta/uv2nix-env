{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch wheels. torch finds CUDA libs via RPATH (the shared patch's driver
# runpath is enough), so no runtime LD_LIBRARY_PATH wiring is needed.
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match =
    n:
    builtins.elem n [
      "torch"
      "torchvision"
      "torchaudio"
    ];
}
