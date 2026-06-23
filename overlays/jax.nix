{
  lib,
  pkgs,
  cuda ? false,
}:
# JAX framework + its CUDA plugin/pjrt wheels (jax-cuda12-plugin, jax-cuda13-pjrt,
# …). Unlike torch, JAX resolves CUDA libs via LD_LIBRARY_PATH at runtime — that
# wiring lives in lib/mk-py-env.nix (the python wrapper), not here; this overlay
# only RPATH-patches the wheels.
let
  patch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  isJax =
    n:
    builtins.elem n [
      "jax"
      "jaxlib"
    ]
    || lib.hasPrefix "jax-cuda" n;
in
_final: prev:
lib.genAttrs (builtins.filter isJax (builtins.attrNames prev)) (n: patch prev.${n} [ ])
