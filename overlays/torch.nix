{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch ecosystem wheels. torch finds its CUDA libs via RPATH (the driver
# runpath from the shared patch under cuda is enough), so no runtime
# LD_LIBRARY_PATH wiring is needed.
let
  basePatch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  names = [
    "torch"
    "torchvision"
    "torchaudio"
  ];
in
{
  matches = n: builtins.elem n names;
  patch = _name: drv: basePatch drv [ ];
}
