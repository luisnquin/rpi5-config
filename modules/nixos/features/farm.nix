{...}: {
  flake.modules.nixos.farm = {
    config,
    lib,
    pkgs,
    ...
  }: let
    farm = pkgs.callPackage ../../../pkgs/farm {};
  in {
    options.services.farm.workloads = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["skinner.service"];
      description = "cgroups always drawn first, even when stopped: a unit under system.slice or a path under /sys/fs/cgroup. Other services and user slices are discovered.";
    };

    config = {
      environment.systemPackages = [farm];

      systemd.services.farm = {
        description = "farm screensaver on tty7";
        wantedBy = ["multi-user.target"];
        after = ["systemd-user-sessions.service"];
        conflicts = ["getty@tty7.service"];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs ([(lib.getExe farm) "--idle" "300" "--night" "1-7"] ++ config.services.farm.workloads);
          StandardInput = "tty";
          StandardOutput = "tty";
          TTYPath = "/dev/tty7";
          TTYReset = true;
          TTYVHangup = true;
          DynamicUser = true;
          AmbientCapabilities = ["CAP_SYS_TTY_CONFIG"];
          CapabilityBoundingSet = ["CAP_SYS_TTY_CONFIG"];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          RestrictAddressFamilies = "AF_UNIX";
          Restart = "always";
          RestartSec = 5;
          Nice = 19;
        };
      };
    };
  };
}
