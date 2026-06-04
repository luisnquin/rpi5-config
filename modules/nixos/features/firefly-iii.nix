{...}: {
  flake.modules.nixos.fireflyIii = {
    config,
    pkgs,
    ...
  }: {
    # Decrypted from secrets/firefly-iii.yaml at activation. The shared db_password
    # is interpolated into both the app and db env files below so the two always
    # agree without the value ever living in the Nix store or the repo in cleartext.
    sops.secrets = {
      app_key = {};
      db_password = {};
      static_cron_token = {};
    };

    sops.templates."firefly-app.env".content = ''
      APP_ENV=production
      APP_DEBUG=false
      APP_KEY=${config.sops.placeholder.app_key}
      APP_NAME=FireflyIII
      APP_URL=http://chimera:8080
      SITE_OWNER=luis@quinones.pro
      DEFAULT_LANGUAGE=en_US
      TZ=America/Lima
      TRUSTED_PROXIES=**
      LOG_CHANNEL=stdout
      APP_LOG_LEVEL=notice
      AUDIT_LOG_LEVEL=emergency
      DB_CONNECTION=mysql
      DB_HOST=firefly-iii-db
      DB_PORT=3306
      DB_DATABASE=firefly
      DB_USERNAME=firefly
      DB_PASSWORD=${config.sops.placeholder.db_password}
      CACHE_DRIVER=file
      SESSION_DRIVER=file
      MAIL_MAILER=log
      STATIC_CRON_TOKEN=${config.sops.placeholder.static_cron_token}
      DKR_CHECK_SQLITE=false
    '';

    sops.templates."firefly-db.env".content = ''
      MARIADB_DATABASE=firefly
      MARIADB_USER=firefly
      MARIADB_PASSWORD=${config.sops.placeholder.db_password}
      MARIADB_RANDOM_ROOT_PASSWORD=yes
    '';

    # The importer reaches core server-to-server over the podman network alias
    # (FIREFLY_III_URL) but redirects the browser to VANITY_URL during OAuth.
    # Mint a Personal Access Token in the UI (Options > Profile > OAuth) after the
    # first login, add it to secrets/firefly-iii.yaml as importer_access_token, and
    # interpolate it here as FIREFLY_III_ACCESS_TOKEN.
    sops.templates."firefly-importer.env".content = ''
      FIREFLY_III_URL=http://firefly-iii:8080
      VANITY_URL=http://chimera:8080
      TZ=America/Lima
      TRUSTED_PROXIES=**
    '';

    virtualisation.podman.enable = true;
    virtualisation.oci-containers = {
      backend = "podman";
      containers = {
        firefly-iii-db = {
          image = "docker.io/library/mariadb:11";
          autoStart = true;
          environmentFiles = [config.sops.templates."firefly-db.env".path];
          volumes = ["/var/lib/firefly-iii/db:/var/lib/mysql"];
          extraOptions = [
            "--network=firefly-iii"
            "--network-alias=firefly-iii-db"
          ];
        };

        firefly-iii = {
          image = "docker.io/fireflyiii/core:version-6.6.3";
          autoStart = true;
          dependsOn = ["firefly-iii-db"];
          environmentFiles = [config.sops.templates."firefly-app.env".path];
          ports = ["8080:8080"];
          volumes = ["/var/lib/firefly-iii/upload:/var/www/html/storage/upload"];
          extraOptions = [
            "--network=firefly-iii"
            "--network-alias=firefly-iii"
          ];
        };

        firefly-iii-importer = {
          image = "docker.io/fireflyiii/data-importer:version-2.3.2";
          autoStart = true;
          dependsOn = ["firefly-iii"];
          environmentFiles = [config.sops.templates."firefly-importer.env".path];
          ports = ["8081:8080"];
          extraOptions = [
            "--network=firefly-iii"
          ];
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/firefly-iii 0700 root root -"
      "d /var/lib/firefly-iii/db 0700 999 999 -"
      "d /var/lib/firefly-iii/upload 0750 33 33 -"
    ];

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

        token="$(cat ${config.sops.secrets.static_cron_token.path})"
        curl -fsS "http://localhost:8080/api/v1/cron/$token"
      '';
    };
  };
}
