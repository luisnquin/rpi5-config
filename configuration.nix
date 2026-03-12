{
  inputs,
  pkgs,
  ...
}: {
  nixpkgs.overlays = [inputs.niri.overlays.niri];

  system.stateVersion = "26.05";
  networking.hostName = "ryx";

  boot.loader.raspberry-pi.bootloader = "kernel";

  # system.nixos.tags = let
  #   cfg = config.boot.loader.raspberry-pi;
  # in [
  #   "raspberry-pi-${cfg.variant}"
  #   cfg.bootloader
  #   config.boot.kernelPackages.kernel.version
  # ];

  users.users.luisnquin = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "video"];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXW6vsDRgI/AiOdGnQOTyiz1uLFL0o66u0Ahcw9VWyd luis@quinones.pro"
    ];
  };

  security = {
    polkit.enable = true;
    sudo.enable = true;
  };

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = ''${pkgs.greetd}/bin/agreety --cmd ${pkgs.lib.getExe pkgs.niri}'';
    };
  };

  programs.niri = {
    enable = true;
    package = pkgs.niri-unstable;
  };

  time.timeZone = "America/New_York";

  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
  '';
}
