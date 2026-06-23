{
  lib,
  pkgs,
  cuda ? false,
}:
# CUDA runtime wheels (nvidia-*; the suffix varies by CUDA major: -cu12 / -cu13 /
# none). These are the shared GPU base that torch and jax both depend on.
let
  patch = import ../lib/patch.nix { inherit lib pkgs cuda; };
in
_final: prev:
lib.genAttrs (builtins.filter (lib.hasPrefix "nvidia-") (builtins.attrNames prev)) (
  n: patch prev.${n} [ ]
)
