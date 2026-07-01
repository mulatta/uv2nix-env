{
  lib,
  pkgs,
  cuda ? false,
  cudaIgnoredMissingDeps ? [ "*" ],
  extraInputs ? { },
}:
# Universal wheel fixup. uv2nix already auto-patchelf's wheels; this overlay
# adds the small gaps in lib/patch.nix to every `passthru.format = "wheel"` drv.
# `extraInputs` is exact-name native-library knowledge only.
let
  patch = import ./patch.nix {
    inherit
      lib
      pkgs
      cuda
      cudaIgnoredMissingDeps
      ;
  };
  isWheel = drv: (drv.passthru.format or "") == "wheel";
in
_final: prev:
lib.mapAttrs (name: drv: if isWheel drv then patch drv (extraInputs.${name} or [ ]) else drv) prev
