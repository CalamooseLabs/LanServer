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
        description = "Command to execute when route is accessed";
        example = [ "echo" "Hello World" ];
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
      description = "List of routes and their associated commands";
      example = [
        {
          path = "/shutdown";
          method = "GET";
          command = [ "shutdown" "0" ];
        }
        {
          path = "/status";
          method = "POST";
          data = { serviceName = "string"; };
          command = [ "systemctl" "status" "$serviceName" ];
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

    # Create the systemd service
    systemd.services.lanserver = {
      description = "LAN Command Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = if cfg.runAsRoot then "root" else "lanserver";
        Group = if cfg.runAsRoot then "root" else "lanserver";
        ExecStart = "${cfg.package}/bin/deno run --allow-read --allow-run --allow-net ${./server.ts}";
        Restart = "always";
        RestartSec = "10";

        # Security settings (when not running as root)
      } // (optionalAttrs (!cfg.runAsRoot) {
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/tmp" ];
      });

      environment = {
        DENO_DIR = "/var/cache/deno";
      };
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

