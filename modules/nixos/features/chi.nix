{inputs, ...}: {
  flake.modules.nixos.chi = {
    config,
    lib,
    pkgs,
    ...
  }: let
    chi = inputs.chi.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
          | curl -fsS --max-time 10 -H "Title: chi $(printf '%s' "$event" | jq -r .org)" \
            -H "Priority: $priority" -H "Click: $(printf '%s' "$event" | jq -r .url)" \
            --data-binary @- http://nyx:2586/notifications >/dev/null
      '';
    };

    hooks = pkgs.linkFarm "chi-hooks" [
      {
        name = "ntfy";
        path = lib.getExe ntfy;
      }
    ];
  in {
    imports = [inputs.agenix.nixosModules.default];

    environment.systemPackages = [chi pkgs.sqlite];

    age.secrets.cloudflared-chimera.file = ../../../secrets/cloudflared-chimera.age;

    services.cloudflared = {
      enable = true;
      tunnels."8197aee8-115d-4af3-abaa-bbd9ae1fb596" = {
        credentialsFile = config.age.secrets.cloudflared-chimera.path;
        default = "http_status:404";
        ingress = {
          "chi.nshard.com" = origin;
          # Senders built before the rename still report here.
          "chimera.nshard.com" = origin;
        };
      };
    };

    # DNS comes from tailscale, which lags network-online at boot; 100ms restarts hit the start limit first.
    systemd.services."cloudflared-tunnel-8197aee8-115d-4af3-abaa-bbd9ae1fb596".serviceConfig.RestartSec = 5;

    systemd.services.chi = {
      description = "chi suite";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target"];
      environment = {
        CHI_URL = "https://chi.nshard.com";
        CHI_DATA = "/var/lib/chi";
        CHI_LISTEN = "127.0.0.1:${toString port}";
        CHI_HOOKS = "${hooks}";
        # glibc otherwise keeps a freed 19 MiB password hash resident.
        MALLOC_ARENA_MAX = "1";
        MALLOC_MMAP_THRESHOLD_ = "65536";
        MALLOC_TRIM_THRESHOLD_ = "65536";
      };
      serviceConfig = {
        ExecStart = "${lib.getExe chi} serve";
        DynamicUser = true;
        StateDirectory = "chi";
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
