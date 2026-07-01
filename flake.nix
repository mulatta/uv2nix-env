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
      # Public API: env builders and helpers for project-local overrides.
      lib = {
        inherit mkWorkspace mkPyEnv mkDevShell;

        # The shared per-wheel fixup ({ lib, pkgs, cuda } -> drv -> extraInputs ->
        # drv'). mkWorkspace applies it to every wheel automatically; exposed for
        # use inside a project's own `overrides` when hand-patching a package.
        mkPatch = import ./lib/patch.nix;

        # Give a package a build-system it forgot to declare. Use as:
        #   overrides = final: prev: { fbpca = addBuildSystem final { setuptools = [ ]; } prev.fbpca; };
        addBuildSystem =
          final: buildSystems: drv:
          drv.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem buildSystems;
          });
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
        let
          exampleWorkspace = mkWorkspace {
            inherit pkgs;
            workspaceRoot = ./example;
            name = "example-venv";
          };
        in
        {
          example = exampleWorkspace.venv;
        }
        // exampleWorkspace.venvs {
          example-mainprogram = {
            mainProgram = "python";
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
        { pkgs, system, ... }:
        {
          formatting = treefmtEval.${system}.config.build.check self;
          example = self.packages.${system}.example;
          example-mainprogram =
            pkgs.runCommand "example-mainprogram-check"
              {
                mainProgram = self.packages.${system}.example-mainprogram.meta.mainProgram or "";
              }
              ''
                test "$mainProgram" = python
                touch "$out"
              '';
        }
      );

      formatter = eachSystem ({ system, ... }: treefmtEval.${system}.config.build.wrapper);
    };
}
