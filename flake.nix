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

      # Target architecture for deno compile
      target =
        if system == "x86_64-linux"
        then "x86_64-unknown-linux-gnu"
        else if system == "aarch64-linux"
        then "aarch64-unknown-linux-gnu"
        else throw "Unsupported system: ${system}";

      # Step 1: Cache dependencies in a separate derivation
      denoCache = pkgs.stdenv.mkDerivation {
        name = "lanserver-deno-cache";
        src = ./.;
        nativeBuildInputs = with pkgs; [deno];

        buildPhase = ''
          export DENO_DIR=./.deno
          mkdir $DENO_DIR

          # Cache dependencies
          ${pkgs.lib.optionalString (builtins.pathExists ./deno.lock) ''
            deno cache --reload --lock=deno.lock src/main.ts
          ''}
          ${pkgs.lib.optionalString (!builtins.pathExists ./deno.lock) ''
            deno cache --reload src/main.ts
          ''}
        '';

        installPhase = ''
          mkdir $out
          cp -r .deno/deps $out/ || true
          cp -r .deno/npm $out/ || true
          cp -r .deno/gen $out/ || true
        '';

        outputHashMode = "recursive";
        outputHashAlgo = "sha256";
        outputHash = "sha256-iFh0uG2ntpClgsGqgfIRIrp4oQwHQca/iY/CYNx8Ryw=";
      };

      # Step 2: Fetch the denort binary (not deno binary!)
      denortZip = pkgs.fetchurl {
        url = "https://dl.deno.land/release/v${pkgs.deno.version}/denort-${target}.zip";
        sha256 = "sha256-qCuGkPfCb23wgFoRReAhCPQ3o6GtagWnIyuuAdqw7Ns=";
      };
    in {
      # Step 3: Final compilation derivation
      lanserver = pkgs.stdenv.mkDerivation {
        name = "lanserver";
        version = "1.0.0";
        src = ./.;

        nativeBuildInputs = with pkgs; [
          deno
          unzip
          # autoPatchelfHook # Essential for NixOS
        ];

        # Disable automatic ELF patching
        dontAutoPatchELF = true;
        dontStrip = true;

        buildInputs = with pkgs; [
          stdenv.cc.cc.lib
          glibc
        ];

        configurePhase = ''
          echo "Setting up Deno cache and denort binary"
          export DENO_DIR=.deno
          mkdir $DENO_DIR

          # Link cached dependencies
          ln -s ${denoCache}/deps $DENO_DIR/deps || true
          ln -s ${denoCache}/npm $DENO_DIR/npm || true
          ln -s ${denoCache}/gen $DENO_DIR/gen || true

          # Extract denort binary from zip
          mkdir -p ./denort-temp
          cd ./denort-temp
          unzip ${denortZip}
          cd ..

          # Set DENORT_BIN to point to the extracted binary
          export DENORT_BIN="$(pwd)/denort-temp/denort"
          chmod +x "$DENORT_BIN"
        '';

        buildPhase = ''
          deno compile \
            --allow-read=/etc/lanserver \
            --allow-run \
            --allow-net \
            --allow-env=PATH,HOME,USER,DENO_DIR \
            --cached-only \
            ${pkgs.lib.optionalString (builtins.pathExists ./deno.lock) "--lock deno.lock"} \
            --output ./lanserver \
            --target=${target} \
            src/main.ts
        '';

        installPhase = ''
          mkdir -p $out/bin
          cp lanserver $out/bin/
          chmod +x $out/bin/lanserver
        '';
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
