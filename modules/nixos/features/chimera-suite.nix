{inputs, ...}: {
  flake.modules.nixos.chimeraSuite = {
    config,
    lib,
    pkgs,
    ...
  }: let
    chimera = inputs.chimera-suite.packages.${pkgs.stdenv.hostPlatform.system}.default;
    port = 8377;
    origin = "http://127.0.0.1:${toString port}";

    ntfy = pkgs.writeShellApplication {
      name = "ntfy";
      runtimeInputs = [pkgs.curl pkgs.jq];
      text = ''
        event=$(cat)
        priority=default
        case "$(printf '%s' "$event" | jq -r .type)" in
          issue.new | issue.regressed | build.failed) priority=high ;;
        esac
        printf '%s' "$event" \
          | jq -r '[.type, .repo // .project, .version // .title, .culprit] | map(select(. and . != "")) | join(" ")' \
          | curl -fsS --max-time 10 -H "Title: chimera $(printf '%s' "$event" | jq -r .org)" \
            -H "Priority: $priority" -H "Click: $(printf '%s' "$event" | jq -r .url)" \
            --data-binary @- http://nyx:2586/chimera >/dev/null
      '';
    };

    hooks = pkgs.linkFarm "chimera-hooks" [
      {
        name = "ntfy";
        path = lib.getExe ntfy;
      }
    ];
  in {
    imports = [inputs.agenix.nixosModules.default];

    environment.systemPackages = [chimera];

    age.secrets.cloudflared-chimera.file = ../../../secrets/cloudflared-chimera.age;

    services.cloudflared = {
      enable = true;
      tunnels."8197aee8-115d-4af3-abaa-bbd9ae1fb596" = {
        credentialsFile = config.age.secrets.cloudflared-chimera.path;
        default = "http_status:404";
        ingress = {
          "chimera.nshard.com" = origin;
          "cuentacero-chimera.nshard.com" = origin;
        };
      };
    };

    systemd.services.chimera = {
      description = "chimera suite";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      environment = {
        CHIMERA_URL = "https://chimera.nshard.com";
        CHIMERA_DATA = "/var/lib/chimera";
        CHIMERA_LISTEN = "127.0.0.1:${toString port}";
        CHIMERA_HOOKS = "${hooks}";
        # glibc otherwise keeps a freed 19 MiB password hash resident.
        MALLOC_ARENA_MAX = "1";
        MALLOC_MMAP_THRESHOLD_ = "65536";
        MALLOC_TRIM_THRESHOLD_ = "65536";
      };
      serviceConfig = {
        ExecStart = "${lib.getExe chimera} serve";
        DynamicUser = true;
        StateDirectory = "chimera";
        Restart = "always";
        RestartSec = 5;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };
  };
}
