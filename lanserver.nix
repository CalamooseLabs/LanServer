{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.lanserver;

  routeType = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = "HTTP path for the route";
        example = "/shutdown";
      };

      method = mkOption {
        type = types.enum [ "GET" "POST" "PUT" "DELETE" ];
        default = "GET";
        description = "HTTP method for the route";
      };

      command = mkOption {
        type = types.listOf types.str;
        description = "Command strings to execute when route is accessed";
        example = [ "echo 'Shutting down...'" "shutdown 0" ];
      };

      data = mkOption {
        type = types.nullOr (types.attrsOf types.str);
        default = null;
        description = "Expected data fields for POST requests";
        example = { serviceName = "string"; };
      };
    };
  };

  configFile = pkgs.writeText "lanserver-config.json" (builtins.toJSON {
    port = cfg.port;
    runAsRoot = cfg.runAsRoot;
    routes = cfg.routes;
  });

  serverScript = pkgs.writeText "server.ts" ''
    ${builtins.readFile ./server.ts}
  '';

in {
  options.services.lanserver = {
    enable = mkEnableOption "LAN command server";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };

    runAsRoot = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to run the server as root";
    };

    routes = mkOption {
      type = types.listOf routeType;
      default = [];
      description = "List of routes and their associated command strings";
      example = [
        {
          path = "/shutdown";
          method = "GET";
          command = [ "echo 'Shutting down...'" "shutdown 0" ];
        }
        {
          path = "/status";
          method = "POST";
          data = { serviceName = "string"; };
          command = [ "systemctl status $serviceName" ];
        }
      ];
    };

    package = mkOption {
      type = types.package;
      default = pkgs.deno;
      description = "Deno package to use";
    };
  };

  config = mkIf cfg.enable {
    # Create config directory and file
    environment.etc."lanserver/config.json".source = configFile;
    environment.etc."lanserver/server.ts".source = serverScript;

    # Create the systemd service
    systemd.services.lanserver = {
      description = "LAN Command Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      # Ensure proper PATH is available for the service
      path = with pkgs; [
        bash
        coreutils
        systemd
        util-linux
        # Add other packages your commands might need
      ] ++ (if cfg.runAsRoot then [ pkgs.sudo ] else []);

      serviceConfig = {
        Type = "simple";
        User = if cfg.runAsRoot then "root" else "lanserver";
        Group = if cfg.runAsRoot then "root" else "lanserver";
        ExecStart = "${cfg.package}/bin/deno run --allow-read --allow-run --allow-net --allow-env /etc/lanserver/server.ts";
        Restart = "always";
        RestartSec = "10";

        # Ensure PATH includes system binaries
        Environment = [
          "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin"
          "DENO_DIR=/var/cache/deno"
        ];

        # Security settings (when not running as root)
      } // (optionalAttrs (!cfg.runAsRoot) {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/tmp" "/var/cache/deno" ];
      });
    };

    # Create user if not running as root
    users.users = mkIf (!cfg.runAsRoot) {
      lanserver = {
        isSystemUser = true;
        group = "lanserver";
        description = "LAN server user";
      };
    };

    users.groups = mkIf (!cfg.runAsRoot) {
      lanserver = {};
    };

    # Create cache directory
    systemd.tmpfiles.rules = [
      "d /var/cache/deno 0755 ${if cfg.runAsRoot then "root" else "lanserver"} ${if cfg.runAsRoot then "root" else "lanserver"} -"
    ];

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
