{
  lib,
  pkgs,
  cuda ? false,
}:
# CUDA runtime wheels (nvidia-*; suffix varies by CUDA major: -cu12 / -cu13 /
# none). The shared GPU base that torch/jax/rapids all depend on.
# Concern rule: { matches = name -> bool; patch = name -> drv -> drv'; }
let
  basePatch = import ../lib/patch.nix { inherit lib pkgs cuda; };
in
{
  matches = lib.hasPrefix "nvidia-";
  patch = _name: drv: basePatch drv [ ];
}
