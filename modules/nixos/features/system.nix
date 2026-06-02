{...}: {
  flake.modules.nixos.system = {
    system.stateVersion = "25.11";
    networking.hostName = "chimera";
    time.timeZone = "America/El_Salvador";
  };
}
