{inputs, ...}: {
  flake.modules.homeManager.zenBrowser = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.zen-browser-flake.homeModules.beta];

    programs.zen-browser = {
      enable = true;

      policies.DisableAppUpdate = true;

      profiles.default = {
        spaces."General" = {
          id = "c6de089c-410d-4206-961d-ab11f988d40a";
          position = 1000;
          pins."GitHub" = {
            id = "48e8a119-5a14-4826-9545-91c8e8dd3bf6";
            url = "https://github.com";
            position = 101;
          };
        };

        keyboardShortcuts = [
          {
            id = "zen-compact-mode-toggle";
            key = "c";
            modifiers = {
              control = true;
              alt = true;
            };
          }
          {
            id = "key_quitApplication";
            disabled = true;
          }
        ];
      };
    };

    # On demand, never at login: the flake's state writers skip a profile Zen holds locked.
    systemd.user.services = {
      zen-headless = {
        Unit.Description = "Zen browser on the declared profile, headless, Marionette on 127.0.0.1:2828";
        Service = {
          ExecStart = "${lib.getExe' config.programs.zen-browser.finalPackage "zen-beta"} --headless --marionette";
          Environment = ["MOZ_REMOTE_ALLOW_SYSTEM_ACCESS=1"];
        };
      };
      zen-webdriver = {
        Unit = {
          Description = "W3C WebDriver for zen-headless on 127.0.0.1:4444";
          BindsTo = ["zen-headless.service"];
          After = ["zen-headless.service"];
        };
        Service.ExecStart = "${lib.getExe pkgs.geckodriver} --connect-existing --marionette-port 2828 --host 127.0.0.1 --port 4444";
      };
    };
  };
}
