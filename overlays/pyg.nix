{
  lib,
  pkgs,
  cuda ? false,
}:
# PyTorch Geometric C-extension wheels (torch-scatter / -sparse / -cluster /
# -spline-conv / pyg-lib). These are prebuilt binaries linked against libtorch
# and the CUDA runtime, so they need exactly the torch wheel treatment:
# autoPatchelf for the usual native libs plus the host driver runpath, with the
# libtorch/libc10/libcuda deps left unresolved at build time — `import torch`
# loads them into the process first, so the extension .so resolve them at import.
#
# Note: these wheels are served from PyG's flat index (data.pyg.org), which
# publishes no hashes. That is a *lockfile* concern, not a build one: the
# consumer must complete the missing sha256 in their uv.lock (uv preserves
# manually-provided hashes). This concern only does the post-fetch ELF fixup.
let
  basePatch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  names = [
    "torch-scatter"
    "torch-sparse"
    "torch-cluster"
    "torch-spline-conv"
    "pyg-lib"
  ];
in
{
  matches = n: builtins.elem n names;
  patch = _name: drv: basePatch drv [ ];
}
