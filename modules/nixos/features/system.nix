{...}: {
  flake.modules.nixos.system = {
    system.stateVersion = "26.05";
    networking.hostName = "ryx";
    time.timeZone = "America/New_York";
  };
}
