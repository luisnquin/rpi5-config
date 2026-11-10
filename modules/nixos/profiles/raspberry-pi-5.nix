{inputs, ...}: {
  flake.modules.nixos.raspberryPi5 = {pkgs, ...}: {
    imports = with inputs.nixos-raspberrypi.nixosModules; [
      raspberry-pi-5.base
      raspberry-pi-5.display-vc4
      inputs.self.modules.nixos.raspberryPiFirmware
    ];

    boot.kernelPackages = let
      shim = k:
        k
        // {
          target = "Image";
          buildDTBs = true;
          override = f: shim (k.override f);
        };
    in
      inputs.nixos-raspberrypi.packages.${pkgs.stdenv.hostPlatform.system}.linuxPackages_rpi5.extend (_: super: {
        kernel = shim super.kernel;
      });

    hardware.raspberry-pi.config.all.base-dt-params.pciex1_gen = {
      enable = true;
      value = 3;
    };
  };
}
