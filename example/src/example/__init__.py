"""Minimal package so uv2nix has a workspace to build and lock."""


def main() -> None:
    import numpy  # noqa: F401  (binary wheel -> exercises the autoPatchelf override)

    print("bioinformatics-py-overrides example env OK")
