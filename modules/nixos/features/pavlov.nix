{inputs, ...}: {
  flake.modules.nixos.pavlov = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # The Pi 5 gangs VBUS across all four onboard ports: it only drops once every root hub is off.
    usbPower = pkgs.writeShellApplication {
      name = "usb-power";
      runtimeInputs = [pkgs.uhubctl];
      text = ''
        case "''${1-}" in 0 | 1) ;; *) echo "usage: usb-power 0|1" >&2; exit 64 ;; esac
        for hub in 1 2 3 4; do uhubctl -l "$hub" -a "$1" >/dev/null; done
      '';
    };

    pavlovCharge = pkgs.writeShellApplication {
      name = "pavlov-charge";
      runtimeInputs = [
        (pkgs.callPackage ../../../pkgs/skinner {})
        (pkgs.callPackage "${inputs.nixos-config}/pkgs/phone" {})
        pkgs.android-tools
      ];
      text = ''
        power() { ${config.security.wrapperDir}/sudo ${lib.getExe usbPower} "$1"; }

        if [[ $(skinner status) == running* ]]; then
          power 1
          exit
        fi

        level=$(phone run -t pavlov -- adb shell dumpsys battery </dev/null | sed -n 's/^ *level: *//p' | tr -d '\r') || level=
        if [[ ! $level =~ ^[0-9]+$ ]]; then
          echo "pavlov-charge: no battery level, charging" >&2
          power 1
        elif ((level >= 80)); then
          power 0
        elif ((level <= 40)); then
          power 1
        fi
      '';
    };
  in {
    # skinner drives pavlov over USB without a seat, so uaccess never grants it.
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{serial}=="X9F4C20115001536", OWNER="luisnquin"
    '';

    environment.systemPackages = [usbPower];

    security.sudo.extraRules = [
      {
        users = ["luisnquin"];
        commands = [
          {
            command = lib.getExe usbPower;
            options = ["NOPASSWD"];
          }
        ];
      }
    ];

    systemd.services.pavlov-charge = {
      description = "pavlov battery charge window";
      environment.PHONE_AGENT = "skinner";
      serviceConfig = {
        Type = "oneshot";
        User = "luisnquin";
        ExecStart = lib.getExe pavlovCharge;
      };
    };

    systemd.timers.pavlov-charge = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
