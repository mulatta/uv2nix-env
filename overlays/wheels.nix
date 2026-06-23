{
  lib,
  pkgs,
  cuda ? false,
}:
# Generic prebuilt binary wheels not tied to a framework, but which still bundle
# ELF needing RPATH fixes (e.g. numpy/scipy's OpenBLAS). Extend as needed.
let
  patch = import ../lib/patch.nix { inherit lib pkgs cuda; };
  names = [
    "numpy"
    "scipy"
  ];
in
_final: prev:
lib.genAttrs (builtins.filter (n: builtins.hasAttr n prev) names) (n: patch prev.${n} [ ])
