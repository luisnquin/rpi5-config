{inputs, ...}: {
  flake.modules.nixos.chi = {
    config,
    lib,
    pkgs,
    ...
  }: let
    port = 8377;
    origin = "http://127.0.0.1:${toString port}";

    # skinner owns nixpkgs.config.allowUnfreePredicate; claude-code comes from its own instance.
    unfree = import pkgs.path {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };

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
  in {
    imports = [inputs.agenix.nixosModules.default inputs.chi.nixosModules.default];

    environment.systemPackages = [config.services.chi.package pkgs.sqlite];

    age.secrets = {
      cloudflared-chimera.file = ../../../secrets/cloudflared-chimera.age;
      chi-github.file = ../../../secrets/chi-github.age;
    };

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

    services.chi = {
      enable = true;
      url = "https://chi.nshard.com";
      listen = "127.0.0.1:${toString port}";
      hooks.ntfy = lib.getExe ntfy;
      agents = [unfree.claude-code pkgs.codex];
      githubSecretFile = config.age.secrets.chi-github.path;
    };

    systemd.services.chi = {
      environment = {
        # glibc otherwise keeps a freed 19 MiB password hash resident.
        MALLOC_ARENA_MAX = "1";
        MALLOC_MMAP_THRESHOLD_ = "65536";
        MALLOC_TRIM_THRESHOLD_ = "65536";
      };
      serviceConfig = {
        Restart = lib.mkForce "always";
        RestartSec = 5;
      };
    };
  };
}
