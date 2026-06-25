{
  lib,
  pkgs,
  cuda ? false,
}:
# CUDA runtime wheels (nvidia-*): the shared GPU base torch/jax/rapids depend on.
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match = lib.hasPrefix "nvidia-";
}
