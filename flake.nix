{
  description = "A flake for the Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    disko,
    ...
  }: {
    nixosConfigurations.ryx = nixos-raspberrypi.lib.nixosSystemFull {
      specialArgs = inputs // { inherit inputs; };
      modules = [
        ({inputs, ...}: {
          disabledModules = ["${inputs.nixpkgs}/nixos/modules/rename.nix"];

          imports = with nixos-raspberrypi.nixosModules; [
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
            raspberry-pi-5.display-vc4
            ./config-txt.nix
          ];
        })
        disko.nixosModules.disko
        ./disko-usb-btrfs.nix
        {
          boot.tmp.useTmpfs = true;
        }
        ./configuration.nix
      ];
    };
  };
}
