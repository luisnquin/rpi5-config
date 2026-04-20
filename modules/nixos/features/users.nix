{...}: {
  flake.modules.nixos.users = {pkgs, ...}: {
    programs.zsh.enable = true;

    users.users = {
      root.hashedPassword = "$6$djOTUxEpFIXIRtd3$RfBMFRLcgsaAWSRg.sHCQv87WRX3jE0gRpinMJwpu7cBk1HT2EaOzhGC829jlRVV7v4lMvMO99xmzAJWL/Exg.";

      luisnquin = {
        isNormalUser = true;
        shell = pkgs.zsh;
        hashedPassword = "$6$djOTUxEpFIXIRtd3$RfBMFRLcgsaAWSRg.sHCQv87WRX3jE0gRpinMJwpu7cBk1HT2EaOzhGC829jlRVV7v4lMvMO99xmzAJWL/Exg.";
        extraGroups = ["wheel" "networkmanager" "video"];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXW6vsDRgI/AiOdGnQOTyiz1uLFL0o66u0Ahcw9VWyd luis@quinones.pro"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICOvNB4XZFchiWUCpdXaNcyoyUi9+7SnGCvrRk2CM129"
        ];
      };
    };
  };
}
