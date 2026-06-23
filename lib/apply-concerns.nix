{
  lib,
  pkgs,
  cuda ? false,
  modules,
}:
# Combine the per-concern rule modules (each `{ matches; patch; }`) into ONE
# scope overlay. `attrNames prev` is forced once and every rule filters that
# single list (concerns are disjoint, so order is moot). This keeps the
# per-concern files small/declarative while avoiding N passes over the set.
let
  rules = map (m: import m { inherit lib pkgs cuda; }) modules;
in
_final: prev:
let
  names = builtins.attrNames prev;
in
lib.foldl' (
  acc: r: acc // lib.genAttrs (builtins.filter r.matches names) (n: r.patch n prev.${n})
) { } rules
