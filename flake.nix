{
  description = "LAN Command Server - A web server for executing commands via HTTP routes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zed-editor = {
      url = "github:CalamooseLabs/antlers/flakes.zed-editor?dir=flakes/zed-editor";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {nixpkgs, self, ...} @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {system = system;};
  in {
    devShells.${system}.default = import ./shell.nix {
      inherit pkgs;
      inherit inputs;
    };

    # Export the NixOS module
    nixosModules.lanserver = import ./lanserver.nix;

    # Alternative: you can also use 'default' if you only have one module
    nixosModules.default = import ./lanserver.nix;

    # Optional: provide the Deno server script as a package
    packages = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in {
        lanserver-script = pkgs.writeText "server.ts" (builtins.readFile ./server.ts);
      }
    );
  };
}
