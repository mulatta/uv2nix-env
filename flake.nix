{
  description = "uv2nix python overrides for bioinformatics libraries";

  inputs = {
    # keep-sorted start
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";
    pyproject-build-systems.url = "github:pyproject-nix/build-system-pkgs";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-nix.url = "github:pyproject-nix/pyproject.nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    uv2nix.url = "github:pyproject-nix/uv2nix";
    # keep-sorted end
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      uv2nix,
      pyproject-nix,
      pyproject-build-systems,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f {
            inherit system;
            pkgs = nixpkgs.legacyPackages.${system};
          }
        );

      treefmtEval = eachSystem (
        { pkgs, ... }:
        treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            deadnix.enable = true;
            keep-sorted.enable = true;
            nixfmt.enable = true;
            statix.enable = true;
          };
          # The example workspace is plain Python, not Nix.
          settings.global.excludes = [ "example/**" ];
        }
      );

      # The reusable bits projects import.
      mkPyEnv = import ./lib/mk-py-env.nix {
        inherit (nixpkgs) lib;
        inherit uv2nix pyproject-nix pyproject-build-systems;
      };
    in
    {
      # Public API: the env builder + the raw overrides overlay.
      lib = {
        inherit mkPyEnv;
        overrides = import ./lib/overrides.nix;
      };

      # Light end-to-end self-check: build the example workspace's venv.
      packages = eachSystem (
        { pkgs, ... }:
        {
          example = mkPyEnv {
            inherit pkgs;
            workspaceRoot = ./example;
            name = "example-venv";
          };
        }
      );

      devShells = eachSystem (
        { pkgs, system, ... }:
        {
          default = pkgs.mkShellNoCC {
            packages = [ self.packages.${system}.example ];
          };
        }
      );

      checks = eachSystem (
        { system, ... }:
        {
          formatting = treefmtEval.${system}.config.build.check self;
          example = self.packages.${system}.example;
        }
      );

      formatter = eachSystem ({ system, ... }: treefmtEval.${system}.config.build.wrapper);
    };
}
