{lib, ...}: {
  flake.modules.nixos.openssh = {
    services.openssh = {
      enable = true;
      openFirewall = true;
      ports = [998];
      knownHosts = let
        mkPub = host: key: {
          "${host}-${key.type}" = {
            hostNames = [host];
            publicKey = "ssh-${key.type} ${key.key}";
          };
        };

        mkPubs = host: keys: lib.foldl' (acc: key: acc // mkPub host key) {} keys;
      in
        lib.concatMapAttrs mkPubs {
          "github.com" = [
            {
              type = "ed25519";
              key = "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
            }
            {
              type = "rsa";
              key = "AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=";
            }
          ];
        };
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
