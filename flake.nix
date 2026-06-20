{
  description = "hermes-webui — a web interface for Hermes Agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Required for the agent runtime (run_agent.AIAgent import).
    # The caller should override this to follow their own hermes-agent input
    # when integrating into a downstream flake.
    hermes-agent = {
      url = "github:NousResearch/hermes-agent";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    hermes-agent,
  }: let
    supportedSystems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
  in {
    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      pythonEnv = pkgs.python3.withPackages (ps: with ps; [pyyaml cryptography]);

      webuiSrc = builtins.path {
        path = ./.;
        name = "hermes-webui-src";
        # Exclude Nix-specific files, git, tests, docs from the runtime copy.
        filter = path: type:
          let base = baseNameOf path;
          in !(builtins.elem base [
            ".git" ".direnv" "result" "flake.nix" "flake.lock"
            "tests" "docs" "scripts" "website" ".github"
            "node_modules" "requirements-dev.txt" "pytest.ini"
          ]);
      };

      agentSitePackages = "${hermes-agent}/lib/python3.12/site-packages";
    in {
      default = pkgs.stdenv.mkDerivation {
        pname = "hermes-webui";
        version = "0-unstable-${hermes-agent.shortRev or "local"}";
        src = webuiSrc;
        dontBuild = true;
        dontConfigure = true;
        installPhase = ''
          mkdir -p $out/share/hermes-webui $out/bin
          cp -r . $out/share/hermes-webui/

          cat > $out/bin/hermes-webui <<WRAPPER
          #!${pkgs.runtimeShell}
          # WebUI deps (pyyaml, cryptography) + agent deps (run_agent, openai, etc.)
          export PYTHONPATH="${pythonEnv}/${pythonEnv.sitePackages}:${agentSitePackages}:\''${PYTHONPATH:-}"
          export HERMES_WEBUI_AGENT_DIR="${hermes-agent}"
          exec ${pythonEnv}/bin/python $out/share/hermes-webui/server.py "\$@"
          WRAPPER
          chmod +x $out/bin/hermes-webui
        '';
        meta = {
          description = "A web interface for Hermes Agent";
          homepage = "https://github.com/nesquena/hermes-webui";
          license = pkgs.lib.licenses.mit;
        };
      };
    });

    nixosModules.default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.services.hermes-webui;
    in {
      options.services.hermes-webui = {
        enable = lib.mkEnableOption "Hermes WebUI";

        package = lib.mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} "hermes-webui" {};

        port = lib.mkOption {
          type = lib.types.port;
          default = 8787;
          description = "TCP port the WebUI listens on.";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Address to bind to. Use 0.0.0.0 for all interfaces.";
        };

        passwordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "File containing the WebUI password. Passed as HERMES_WEBUI_PASSWORD_FILE.";
        };

        agentDir = lib.mkOption {
          type = lib.types.path;
          description = ''
            Path to the hermes-agent source checkout. Required — the WebUI
            imports run_agent.AIAgent from this directory at runtime.
          '';
        };

        stateDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/lib/hermes-webui";
          description = "State directory for sessions and settings.";
        };

        extraEnv = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = {};
          description = "Extra environment variables for the service.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "hermes-webui";
          description = "System user the service runs as.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "hermes-webui";
          description = "System group for the service user.";
        };

        openFirewall = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Open the firewall for the WebUI port.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.hermes-webui = {
          description = "Hermes WebUI";
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.group;
            StateDirectory = lib.last (lib.splitString "/" cfg.stateDir);
            WorkingDirectory = cfg.stateDir;
            ExecStart = "${cfg.package}/bin/hermes-webui";
            Restart = "always";
            RestartSec = 5;
            Environment =
              [
                "HERMES_WEBUI_HOST=${cfg.host}"
                "HERMES_WEBUI_PORT=${toString cfg.port}"
                "HERMES_WEBUI_AGENT_DIR=${cfg.agentDir}"
                "HERMES_WEBUI_STATE_DIR=${cfg.stateDir}"
              ]
              ++ lib.optional (cfg.passwordFile != null)
                "HERMES_WEBUI_PASSWORD_FILE=${cfg.passwordFile}"
              ++ lib.mapAttrsToList (n: v: "${n}=${v}") cfg.extraEnv;
          };
        };

        users.users.${cfg.user} = lib.mkDefault {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.stateDir;
          createHome = true;
        };

        users.groups.${cfg.group} = lib.mkDefault {};

        networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];
      };
    };
  };
}
