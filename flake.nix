{
  description = "A flake for the Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    black-terminal.url = "github:luisnquin/black-terminal";
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
      };
    };
  };

  outputs = inputs @ {
    nixos-raspberrypi,
    black-terminal,
    home-manager,
    disko,
    ...
  }: let
    baseModules = [
      {
        imports = with nixos-raspberrypi.nixosModules; [
          raspberry-pi-5.base
          raspberry-pi-5.page-size-16k
          raspberry-pi-5.display-vc4
          ./config-txt.nix
        ];
      }
      disko.nixosModules.disko
      ./disko-usb-btrfs.nix
      {
        boot.tmp.useTmpfs = true;
      }
      home-manager.nixosModules.default
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.luisnquin = {
          imports = [
            black-terminal.homeModules.default
            ./home.nix
          ];
        };
      }
      ./configuration.nix
    ];
  in {
    nixosConfigurations.ryx = nixos-raspberrypi.lib.nixosSystemFull {
      specialArgs = inputs // {inherit inputs;};
      modules = baseModules;
    };
  };
}
