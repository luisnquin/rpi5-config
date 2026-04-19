{inputs, ...}: {
  flake.modules.nixos.base = {
    imports = with inputs.self.modules.nixos; [
      avahi
      boot
      console
      openssh
      security
      system
      udev
      users
    ];
  };
}
