{inputs, ...}: {
  flake.modules.nixos.users = {pkgs, ...}: {
    programs.zsh.enable = true;

    users.users = {
      root.hashedPassword = "$6$djOTUxEpFIXIRtd3$RfBMFRLcgsaAWSRg.sHCQv87WRX3jE0gRpinMJwpu7cBk1HT2EaOzhGC829jlRVV7v4lMvMO99xmzAJWL/Exg.";

      luisnquin = {
        isNormalUser = true;
        linger = true;
        shell = pkgs.zsh;
        hashedPassword = "$6$djOTUxEpFIXIRtd3$RfBMFRLcgsaAWSRg.sHCQv87WRX3jE0gRpinMJwpu7cBk1HT2EaOzhGC829jlRVV7v4lMvMO99xmzAJWL/Exg.";
        extraGroups = ["wheel" "networkmanager" "video"];
        openssh.authorizedKeys.keys = inputs.identity.lib.ssh.authorizedKeys.chimera;
      };
    };
  };
}
