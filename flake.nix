{
  description = "Build uv2nix Python environments (CUDA/native fixups handled)";

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
          # example/ is plain Python, not Nix.
          settings.global.excludes = [ "example/**" ];
        }
      );

      # mkWorkspace is the core; mkPyEnv/mkDevShell are thin aliases onto its outputs.
      mkWorkspace = import ./lib/mk-workspace.nix {
        inherit (nixpkgs) lib;
        inherit
          nixpkgs
          uv2nix
          pyproject-nix
          pyproject-build-systems
          ;
      };
      mkPyEnv = args: (mkWorkspace args).venv;
      mkDevShell = args: (mkWorkspace args).devShell;
    in
    {
      # Public API: env builders, helpers for overrides/extraConcerns, and the raw
      # per-concern rule modules for manual use.
      lib = {
        inherit mkWorkspace mkPyEnv mkDevShell;

        # Shared wheel fixup (autoPatchelf + native libs + driver runpath); use it
        # inside a custom `extraConcerns` entry.
        mkPatch = import ./lib/patch.nix;

        # Build a concern from a name matcher; the terse way to write `extraConcerns`.
        mkConcern = import ./lib/mk-concern.nix;

        # Give a package a build-system it forgot to declare. Use as:
        #   overrides = final: prev: { fbpca = addBuildSystem final { setuptools = [ ]; } prev.fbpca; };
        addBuildSystem =
          final: buildSystems: drv:
          drv.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem buildSystems;
          });

        concerns = {
          cuda = import ./overlays/cuda.nix;
          jax = import ./overlays/jax.nix;
          pyg = import ./overlays/pyg.nix;
          rapids = import ./overlays/rapids.nix;
          torch = import ./overlays/torch.nix;
          wheels = import ./overlays/wheels.nix;
        };
      };

      # Project scaffolds: nix flake init -t github:mulatta/uv2nix-env#<name>
      templates =
        let
          mk = name: desc: {
            path = ./templates/${name};
            description = desc;
          };
        in
        {
          default = mk "default" "uv2nix-env Python project (CPU; pure venv + editable devShell)";
          torch = mk "torch" "PyTorch (CUDA) project using uv2nix-env";
          jax = mk "jax" "JAX (CUDA) + DeepMind project using uv2nix-env";
          rapids = mk "rapids" "RAPIDS cudf (CUDA) project using uv2nix-env";
        };

      # End-to-end self-check: build the example workspace's venv.
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
