{...}: {
  flake.modules.nixos.openssh = {
    services.openssh = {
      enable = true;
      openFirewall = true;
      ports = [998];
      settings = {
        AllowUsers = ["luisnquin"];
        AuthenticationMethods = "publickey";
        ChallengeResponseAuthentication = false;
        ClientAliveCountMax = 3;
        ClientAliveInterval = 60;
        KbdInteractiveAuthentication = false;
        MaxAuthTries = 3;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
        PubkeyAuthentication = true;
        X11Forwarding = false;
      };
    };
  };
}
