{inputs, ...}: {
  flake.modules.nixos.base = {
    imports = with inputs.self.modules.nixos; [
      avahi
      boot
      console
      nix
      remoteAccess
      security
      system
      udev
      users
    ];
  };
}
