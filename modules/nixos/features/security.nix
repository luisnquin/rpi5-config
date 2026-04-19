{...}: {
  flake.modules.nixos.security = {
    security = {
      polkit.enable = true;
      sudo.enable = true;
    };
  };
}
