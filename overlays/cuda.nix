{
  lib,
  pkgs,
  cuda ? false,
}:
# CUDA runtime wheels (nvidia-*; suffix varies by CUDA major: -cu12 / -cu13 /
# none). The shared GPU base that torch/jax/rapids all depend on.
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match = lib.hasPrefix "nvidia-";
}
