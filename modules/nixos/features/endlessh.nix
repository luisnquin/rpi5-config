{...}: {
  flake.modules.nixos.endlessh = {
    services.endlessh = {
      enable = true;
      port = 22;
      openFirewall = true;
    };
  };
}
