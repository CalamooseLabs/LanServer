{
  pkgs,
  inputs,
}: let
  zedSettings = {
    deno = {
      settings = {
        deno = {
          enable = true;
        };
      };
    };
    lsp = {
      nix = {
        binary = {
          path_lookup = true;
        };
      };
      nil = {
        initialization_options = {
          formatting = {
            command = [
              "alejandra"
              "--quiet"
              "--"
            ];
          };
        };
      };
      nixd = {
        initialization_options = {
          formatting = {
            command = [
              "alejandra"
              "--quiet"
              "--"
            ];
          };
        };
      };
    };

    auto_install_extensions = {
      "nix" = true;
      "deno" = true;
    };

    languages = {
      JavaScript = {
        language_servers = [
          "deno"
          "!typescript-language-server"
          "!vtsls"
          "!eslint"
        ];
        formatter = "language_server";
      };
      TypeScript = {
        language_servers = [
          "deno"
          "!typescript-language-server"
          "!vtsls"
          "!eslint"
        ];
        formatter = "language_server";
      };
      nix = {
        formatter = {
          external = {
            command = "alejandra";
            arguments = [
              "--quiet"
              "--"
            ];
          };
        };
      };
    };
  };
in
  pkgs.mkShell {
    packages = [
      pkgs.deno
      pkgs.jq
    ];

    buildInputs = [
      pkgs.alejandra
      pkgs.nixd
      pkgs.nil
      (inputs.zed-editor.packages.x86_64-linux.default zedSettings)
    ];

    shellHook = ''
      echo "Using Local Zed with Deno & Nix"
    '';
  }
