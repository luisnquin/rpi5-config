{
  description = "A flake for the Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    black-terminal.url = "github:luisnquin/black-terminal";
  };

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = inputs @ {
    flake-parts,
    nixos-raspberrypi,
    black-terminal,
    home-manager,
    disko,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["aarch64-linux"];

      flake.nixosConfigurations.ryx = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs // {inherit inputs;};
        modules = [
          disko.nixosModules.disko
          ./disko-nvme-btrfs.nix
          home-manager.nixosModules.default
          {
            imports = with nixos-raspberrypi.nixosModules; [
              raspberry-pi-5.base
              raspberry-pi-5.page-size-16k
              raspberry-pi-5.display-vc4
              ./config-txt.nix
            ];

            boot.tmp.useTmpfs = true;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {inherit inputs;};
            home-manager.users.luisnquin = {
              imports = [
                black-terminal.homeModules.default
                ./home.nix
              ];
            };
          }
          ./configuration.nix
        ];
      };
    };
}
