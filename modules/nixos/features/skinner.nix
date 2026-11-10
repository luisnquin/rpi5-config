{inputs, ...}: {
  flake.modules.nixos.skinner = {
    config,
    lib,
    pkgs,
    ...
  }: let
    skinner = pkgs.callPackage ../../../pkgs/skinner {};
    phone = pkgs.callPackage "${inputs.nixos-config}/pkgs/phone" {};
    secret = name: {
      file = ../../../secrets/${name}.age;
      owner = "luisnquin";
    };
    paths = config.age.secrets;

    pavlovSetup = pkgs.writeShellScript "pavlov-setup" ''
      locked() { adb shell dumpsys window | grep -q 'isStatusBarKeyguard=true'; }
      adb shell input keyevent KEYCODE_WAKEUP
      sleep 1
      if locked; then
        adb shell input swipe 540 1900 540 700 250
        sleep 1
        adb shell input text "$PAVLOV_PIN"
        adb shell input keyevent KEYCODE_ENTER
        sleep 2
        if locked; then
          echo "pavlov-setup: keyguard still up after PIN" >&2
          exit 1
        fi
      fi
      adb shell settings put global hide_error_dialogs 1
    '';

    ntfy = lib.getExe (pkgs.writeShellApplication {
      name = "skinner-ntfy";
      runtimeInputs = [pkgs.curl pkgs.jq];
      text = ''
        event=$(cat)
        kind=$(printf '%s' "$event" | jq -r .event)
        [ "$kind" = queued ] && exit 0
        priority=default
        case "$kind:$(printf '%s' "$event" | jq -r '.status // ""')" in
          device.unreachable:* | report.failed:* | await.timeout:* | finished:failed | finished:error | finished:timeout | finished:unreachable) priority=high ;;
        esac
        printf '%s' "$event" \
          | jq -r '[.repo, .job, .event, .status, .message] | map(select(.)) | join(" ")' \
          | curl -fsS --max-time 10 -H "Title: skinner $(printf '%s' "$event" | jq -r '.run // "chimera"')" \
            -H "Priority: $priority" -H "Tags: robot" --data-binary @- http://nyx:2586/skinner >/dev/null
      '';
    });

    settings = {
      state = "/var/lib/skinner";
      keep = 200;
      hooks = [ntfy];
      hosts.nyx = "ssh -o BatchMode=yes -o ConnectTimeout=5 nyx true";
      devices.pavlov = {
        setup = "${pavlovSetup}";
        env.PAVLOV_PIN = paths.pavlov-pin.path;
      };
      repos.sevastopol = {
        url = "git@github.com:cuentacero/sevastopol.git";
      };
    };
  in {
    imports = [inputs.agenix.nixosModules.default];

    nixpkgs.config = {
      android_sdk.accept_license = true;
      allowUnfreePredicate = pkg: lib.hasPrefix "android-sdk" (lib.getName pkg) || lib.elem (lib.getName pkg) ["cmdline-tools" "platform-tools" "build-tools" "platforms" "tools"];
    };

    age.secrets = lib.genAttrs ["pavlov-pin"] secret;

    environment.etc."skinner/config.json".text = builtins.toJSON settings;
    environment.systemPackages = [skinner phone pkgs.android-tools];

    programs.ssh.extraConfig = ''
      Host nyx
        Port 357
    '';

    systemd.services.skinner = {
      description = "skinner scheduler";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "tailscaled.service"];
      path = [skinner phone config.nix.package] ++ (with pkgs; [android-tools bash coreutils curl git gnugrep jq openssh]);
      environment = {
        PHONE_AGENT = "skinner";
        GIT_CONFIG_GLOBAL = "/dev/null";
      };
      serviceConfig = {
        User = "luisnquin";
        ExecStart = "${lib.getExe skinner} daemon";
        StateDirectory = "skinner";
        Restart = "always";
        RestartSec = 30;
        Nice = 10;
        IOSchedulingClass = "idle";
      };
    };
  };
}
