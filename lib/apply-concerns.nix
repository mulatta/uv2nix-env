{
  lib,
  pkgs,
  cuda ? false,
  modules,
}:
# Combine the per-concern rule modules into ONE scope overlay; `attrNames prev`
# is forced once and every rule filters that single list (concerns are disjoint).
let
  # A module is a path or inline function; both take { lib, pkgs, cuda } -> { matches; patch; }.
  rules = map (m: (if builtins.isFunction m then m else import m) { inherit lib pkgs cuda; }) modules;
in
_final: prev:
let
  names = builtins.attrNames prev;
  # `acc // genAttrs ...` is last-wins: overlapping concerns silently drop the
  # earlier patch. Assert disjointness so an overlap is a build error, not a miss.
  matchedPerRule = map (r: builtins.filter r.matches names) rules;
  allMatched = lib.concatLists matchedPerRule;
  collisions = lib.unique (builtins.filter (n: lib.count (x: x == n) allMatched > 1) allMatched);
in
assert lib.assertMsg (collisions == [ ])
  "uv2nix-env: package(s) matched by more than one concern (last would silently win): ${lib.concatStringsSep ", " collisions}";
lib.foldl' (
  acc: r: acc // lib.genAttrs (builtins.filter r.matches names) (n: r.patch n prev.${n})
) { } rules
