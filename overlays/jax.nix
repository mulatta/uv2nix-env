{
  lib,
  pkgs,
  cuda ? false,
}:
# JAX framework + its CUDA plugin/pjrt wheels (jax-cuda12-plugin, jax-cuda13-pjrt,
# …). JAX resolves CUDA libs via LD_LIBRARY_PATH at runtime — that wiring lives
# in lib/mk-workspace.nix (the python wrapper); this rule only RPATH-patches the
# wheels.
let
  basePatch = import ../lib/patch.nix { inherit lib pkgs cuda; };
in
{
  matches =
    n:
    builtins.elem n [
      "jax"
      "jaxlib"
    ]
    || lib.hasPrefix "jax-cuda" n;
  patch = _name: drv: basePatch drv [ ];
}
