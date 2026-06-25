{
  lib,
  pkgs,
  cuda ? false,
}:
# Build a concern rule from a name matcher. The matched wheels get the shared
# autoPatchelf fixup (lib/patch.nix), optionally with per-package extra
# buildInputs. This is what every built-in overlay uses, and what a project's
# `extraConcerns` entry should use so it stays as terse as the built-ins:
#   (mkConcern { inherit lib pkgs cuda; }) { match = lib.hasPrefix "acme-"; }
let
  basePatch = import ./patch.nix { inherit lib pkgs cuda; };
in
{
  match,
  extraInputs ? (_name: [ ]),
}:
{
  matches = match;
  patch = name: drv: basePatch drv (extraInputs name);
}
