{inputs, ...}: {
  flake.modules.nixos.raspberryPi5 = {
    imports = with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.page-size-16k
      raspberry-pi-5.display-vc4
      inputs.self.modules.nixos.raspberryPiFirmware
    ];
  };
}
