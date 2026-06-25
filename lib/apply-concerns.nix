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
  # A module is a path (built-in concern file) or an inline function (a project's
  # extraConcerns entry); both take { lib, pkgs, cuda } and return { matches; patch; }.
  rules = map (m: (if builtins.isFunction m then m else import m) { inherit lib pkgs cuda; }) modules;
in
_final: prev:
let
  names = builtins.attrNames prev;
in
lib.foldl' (
  acc: r: acc // lib.genAttrs (builtins.filter r.matches names) (n: r.patch n prev.${n})
) { } rules
