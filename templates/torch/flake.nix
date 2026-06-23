{
  description = "torch project using uv2nix-env";

  inputs.uv2nix-env.url = "github:mulatta/uv2nix-env";

  outputs =
    { uv2nix-env, ... }:
    let
      system = "x86_64-linux";
      ws = uv2nix-env.lib.mkWorkspace {
        inherit system;
        workspaceRoot = ./.;
        cuda = true;
      };
    in
    {
      packages.${system}.default = ws.venv; # pure: nix build / nix run
      devShells.${system}.default = ws.devShell; # editable dev shell
    };
}
