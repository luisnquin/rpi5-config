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

    power = state: "${config.security.wrapperDir}/sudo ${lib.getExe usbPower} ${state}";
    phone = pkgs.callPackage "${inputs.nixos-config}/pkgs/phone" {};

    pavlovRecover = pkgs.writeShellApplication {
      name = "pavlov-recover";
      runtimeInputs = [phone pkgs.android-tools pkgs.bash];
      text = ''
        ${power "1"}
        timeout 60 adb wait-for-usb-device
        phone device pin pavlov
      '';
    };

    pavlovCharge = pkgs.writeShellApplication {
      name = "pavlov-charge";
      runtimeInputs = [(pkgs.callPackage ../../../pkgs/skinner {}) phone pkgs.android-tools pkgs.bash pavlovRecover];
      text = ''
        if [[ $(skinner status) == running* ]]; then exec ${power "1"}; fi
        trap 'phone release -t pavlov >/dev/null 2>&1' EXIT

        level=$(phone run -t pavlov -- adb shell dumpsys battery </dev/null | sed -n 's/^ *level: *//p' | tr -d '\r') || level=
        if [[ ! $level =~ ^[0-9]+$ ]]; then
          echo "pavlov-charge: no battery level, recovering" >&2
          pavlov-recover
        elif ((level >= 80)); then
          ${power "0"}
        elif ((level <= 40)); then
          ${power "1"}
        fi
      '';
    };
  in {
    # skinner drives pavlov over USB without a seat, so uaccess never grants it.
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{serial}=="X9F4C20115001536", OWNER="luisnquin"
    '';

    environment.systemPackages = [usbPower];

    systemd.services.skinner.path = [pavlovRecover];

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
      environment.PHONE_AGENT = "pavlov-charge";
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
