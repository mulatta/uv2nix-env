{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch ecosystem wheels. torch resolves its CUDA libs via RPATH (the driver
# runpath added by the shared patch under cuda is enough), so no runtime
# LD_LIBRARY_PATH wiring is needed beyond that.
let
  patch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  names = [
    "torch"
    "torchvision"
    "torchaudio"
  ];
in
_final: prev:
lib.genAttrs (builtins.filter (n: builtins.hasAttr n prev) names) (n: patch prev.${n} [ ])
