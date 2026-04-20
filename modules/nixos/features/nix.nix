{...}: {
  flake.modules.nixos.nix = {pkgs, ...}: {
    nix = {
      gc = {
        automatic = true;
        dates = "daily";
        options = "--delete-older-than 3d";
      };

      settings = rec {
        auto-optimise-store = true;
        keep-outputs = true;
        warn-dirty = false;
        download-attempts = 5;
        experimental-features = ["nix-command" "flakes"];
        trusted-users = ["@wheel"];
        allowed-users = trusted-users;
        max-jobs = 2;
        min-free = 10000000000 * 2; # 20GB
        min-free-check-interval = 30;
        trusted-substituters = [
          "https://cache.nixos.org"
        ];
        substituters = [
          "https://cache.nixos.org"
        ];
      };
    };
  };
}
