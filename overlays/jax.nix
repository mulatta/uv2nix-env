{
  lib,
  pkgs,
  cuda ? false,
}:
# JAX framework + its CUDA plugin/pjrt wheels (jax-cuda12-plugin, jax-cuda13-pjrt,
# …). JAX resolves CUDA libs via LD_LIBRARY_PATH at runtime — that wiring lives
# in lib/mk-workspace.nix (the python wrapper); this rule only RPATH-patches the
# wheels.
(import ../lib/mk-concern.nix { inherit lib pkgs cuda; }) {
  match =
    n:
    builtins.elem n [
      "jax"
      "jaxlib"
    ]
    || lib.hasPrefix "jax-cuda" n;
}
