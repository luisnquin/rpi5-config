{...}: {
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

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;

    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };

    denyInterfaces = ["docker0" "veth*"];
  };

  console.keyMap = "es";

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

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
    };
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
