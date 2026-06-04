{
  flake.modules.nixos.fireflyIii = {pkgs, ...}: {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        firefly-iii-db = {
          image = "docker.io/library/mariadb:11.4.12@sha256:1b46b73d4b629022dfa29e6db3bb0d63b5df714fc3bfbe5057d63d76d8f6054b";
          autoStart = true;
          environment = {
            MARIADB_DATABASE = "firefly";
            MARIADB_USER = "firefly";
            MARIADB_RANDOM_ROOT_PASSWORD = "yes";
          };
          environmentFiles = ["/var/lib/firefly-iii/secrets/db.env"];
          volumes = ["/var/lib/firefly-iii/db:/var/lib/mysql"];
          extraOptions = [
            "--network=firefly-iii"
            "--network-alias=firefly-iii-db"
            "--health-cmd=healthcheck.sh --connect --innodb_initialized"
            "--health-interval=10s"
            "--health-timeout=5s"
            "--health-retries=6"
            "--health-start-period=30s"
          ];
        };

        firefly-iii = {
          # Firefly rebuilds version-X.Y.Z tags in place on base-image patches,
          # so the digest is what makes this reproducible.
          image = "docker.io/fireflyiii/core:version-6.6.3@sha256:4d63328dbc7c60ef5a8269bb2ee89f120b28f88eb0395e4211e23f93fd79337f";
          autoStart = true;
          dependsOn = ["firefly-iii-db"];
          environment = {
            APP_ENV = "production";
            APP_DEBUG = "false";
            APP_NAME = "FireflyIII";
            APP_URL = "http://chimera:8080";
            SITE_OWNER = "luis@quinones.pro";
            DEFAULT_LANGUAGE = "en_US";
            TZ = "America/Lima";
            TRUSTED_PROXIES = "**";
            LOG_CHANNEL = "stdout";
            APP_LOG_LEVEL = "notice";
            AUDIT_LOG_LEVEL = "emergency";
            DB_CONNECTION = "mysql";
            DB_HOST = "firefly-iii-db";
            DB_PORT = "3306";
            DB_DATABASE = "firefly";
            DB_USERNAME = "firefly";
            CACHE_DRIVER = "file";
            SESSION_DRIVER = "file";
            MAIL_MAILER = "log";
            DKR_CHECK_SQLITE = "false";
          };
          environmentFiles = ["/var/lib/firefly-iii/secrets/app.env"];
          ports = ["8080:8080"];
          volumes = ["/var/lib/firefly-iii/upload:/var/www/html/storage/upload"];
          extraOptions = [
            "--network=firefly-iii"
            "--network-alias=firefly-iii"
          ];
        };

        firefly-iii-importer = {
          image = "docker.io/fireflyiii/data-importer:version-2.3.2@sha256:4e2cbcb0d95c34850534a3772f1732c00f6412077db33b1863703a1b628bdc12";
          autoStart = true;
          dependsOn = ["firefly-iii"];
          # The importer reaches core server-to-server over the podman network
          # alias (FIREFLY_III_URL) but redirects the browser to VANITY_URL during
          # OAuth. To automate imports, mint a Personal Access Token in the UI
          # (Options > Profile > OAuth) and append FIREFLY_III_ACCESS_TOKEN=<token>
          # to a file referenced from environmentFiles here.
          environment = {
            FIREFLY_III_URL = "http://firefly-iii:8080";
            VANITY_URL = "http://chimera:8080";
            TZ = "America/Lima";
            TRUSTED_PROXIES = "**";
          };
          ports = ["8081:8080"];
          extraOptions = [
            "--network=firefly-iii"
          ];
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/firefly-iii 0700 root root -"
      "d /var/lib/firefly-iii/secrets 0700 root root -"
      "d /var/lib/firefly-iii/db 0700 999 999 -"
      "d /var/lib/firefly-iii/upload 0750 33 33 -"
    ];

    systemd.services.firefly-iii-secrets = {
      wantedBy = ["multi-user.target"];
      requiredBy = [
        "podman-firefly-iii.service"
        "podman-firefly-iii-db.service"
      ];
      before = [
        "podman-firefly-iii.service"
        "podman-firefly-iii-db.service"
      ];
      path = [pkgs.coreutils];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # No pipefail: `tr | head -c` closes the pipe early and kills tr with
      # SIGPIPE, which pipefail would turn into a spurious failure.
      script = ''
        set -eu

        secdir=/var/lib/firefly-iii/secrets
        mkdir -p "$secdir"
        chmod 0700 "$secdir"

        gen() {
          tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"
        }

        if [ ! -e "$secdir/app.env" ]; then
          db_password="$(gen 32)"

          umask 077
          {
            printf 'APP_KEY=%s\n' "$(gen 32)"
            printf 'DB_PASSWORD=%s\n' "$db_password"
            printf 'STATIC_CRON_TOKEN=%s\n' "$(gen 32)"
          } > "$secdir/app.env"

          printf 'MARIADB_PASSWORD=%s\n' "$db_password" > "$secdir/db.env"
        fi
      '';
    };

    systemd.services.firefly-iii-network = {
      wantedBy = ["multi-user.target"];
      requiredBy = [
        "podman-firefly-iii.service"
        "podman-firefly-iii-db.service"
        "podman-firefly-iii-importer.service"
      ];
      before = [
        "podman-firefly-iii.service"
        "podman-firefly-iii-db.service"
        "podman-firefly-iii-importer.service"
      ];
      path = [pkgs.podman];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        if ! podman network exists firefly-iii; then
          podman network create firefly-iii
        fi
      '';
    };

    # Firefly III has no internal scheduler: recurring transactions, bill reminders
    # and auto-budgets only advance when GET /api/v1/cron/[token] is called.
    systemd.timers.firefly-iii-cron = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
      };
    };

    systemd.services.firefly-iii-cron = {
      after = ["podman-firefly-iii.service"];
      path = [pkgs.curl pkgs.coreutils];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail

        set -a
        . /var/lib/firefly-iii/secrets/app.env
        set +a
        curl -fsS "http://localhost:8080/api/v1/cron/$STATIC_CRON_TOKEN"
      '';
    };
  };
}
