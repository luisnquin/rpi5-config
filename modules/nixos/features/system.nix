{...}: {
  flake.modules.nixos.system = {
    system.stateVersion = "26.05";
    networking.hostName = "chimera";
    time.timeZone = "America/El_Salvador";
  };
}
