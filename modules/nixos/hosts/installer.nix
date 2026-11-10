{inputs, ...}: {
  flake.modules.nixos.installer = {
    config,
    lib,
    modulesPath,
    pkgs,
    ...
  }: {
    imports = [
      inputs.nixos-raspberrypi.inputs.nixos-images.nixosModules.sdimage-installer
      inputs.self.modules.nixos.raspberryPi5
      inputs.self.modules.nixos.users
    ];

    disabledModules = [(modulesPath + "/installer/sd-card/sd-image-aarch64-installer.nix")];
    image.baseName = lib.mkOverride 40 "nixos-installer-rpi5-${config.boot.loader.raspberry-pi.bootloader}";
    networking.wireless.enable = lib.mkForce false;

    boot.supportedFilesystems.zfs = lib.mkForce false;
    environment.systemPackages = [pkgs.raspberrypi-eeprom];

    users.users.root = {
      initialHashedPassword = lib.mkForce null;
      openssh.authorizedKeys.keys = config.users.users.luisnquin.openssh.authorizedKeys.keys;
    };
  };
}
