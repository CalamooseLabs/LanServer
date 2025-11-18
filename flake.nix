{
  description = "LAN Command Server - A web server for executing commands via HTTP routes";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    zed-editor = {
      url = "github:CalamooseLabs/antlers/flakes.zed-editor?dir=flakes/zed-editor";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    self,
    ...
  } @ inputs: let
    supportedSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {
    # Use forAllSystems for devShells too
    devShells = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = import ./shell.nix {
        inherit pkgs;
        inherit inputs;
      };
    });

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      lanserver = pkgs.stdenv.mkDerivation {
        pname = "lanserver";
        version = "1.0.0";
        src = ./.;

        nativeBuildInputs = [pkgs.deno];

        buildPhase = ''
          runHook preBuild

          # Set up Deno cache directory
          export DENO_DIR=$TMPDIR/deno_cache

          # Cache dependencies if deno.lock exists
          ${pkgs.lib.optionalString (builtins.pathExists ./deno.lock) ''
            echo "Caching dependencies from deno.lock..."
            deno cache --lock=deno.lock src/main.ts
          ''}

          # Compile to binary with specific permissions
          deno compile \
            --allow-read=/etc/lanserver \
            --allow-run \
            --allow-net \
            --allow-env=PATH,HOME,USER,DENO_DIR \
            --output lanserver \
            src/main.ts

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin
          cp lanserver $out/bin/

          runHook postInstall
        '';

        meta = with pkgs.lib; {
          description = "LAN Command Server - HTTP server for executing system commands";
          license = licenses.mit;
          maintainers = [];
          platforms = platforms.linux;
        };
      };

      default = self.packages.${system}.lanserver;
    });

    # NixOS module
    nixosModules = {
      lanserver = import ./nix/module.nix self;
      default = self.nixosModules.lanserver;
    };

    nixosModule = self.nixosModules.default;
  };
}
