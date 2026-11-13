{
  description = "A flake for the Raspberry Pi 5";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/develop";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    black-terminal.url = "github:luisnquin/black-terminal";
    nixos-config = {
      url = "github:luisnquin/nixos-config";
      flake = false;
    };
    zen-browser-flake = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    identity = {
      url = "github:luisnquin/luisnquin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    chimera-suite = {
      url = "git+ssh://git@chimera/srv/git/0xc000022070/chimera.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    nixpkgs,
    self,
    disko,
    ...
  }: let
    collectTopLevelModules = dir: let
      entries = builtins.readDir dir;
    in
      nixpkgs.lib.concatLists (nixpkgs.lib.mapAttrsToList (
          name: type: let
            path = dir + "/${name}";
          in
            if type == "directory"
            then collectTopLevelModules path
            else if type == "regular" && nixpkgs.lib.hasSuffix ".nix" name && name != "flake.nix" && name != "default.nix"
            then [path]
            else []
        )
        entries);
  in
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [flake-parts.flakeModules.modules] ++ collectTopLevelModules ./modules;

      config = {
        systems = ["aarch64-linux"];

        flake.nixosConfigurations.chimera = nixos-raspberrypi.lib.nixosSystem {
          inherit nixpkgs;
          specialArgs = inputs // {inherit inputs;};
          modules = [
            disko.nixosModules.disko
            black-terminal.nixosModules.default
            home-manager.nixosModules.default
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {inherit inputs;};
              home-manager.users.luisnquin = {
                imports = [
                  black-terminal.homeModules.default
                  self.modules.homeManager.luisnquin
                ];
              };
            }
            self.modules.nixos.chimera
          ];
        };

        flake.nixosConfigurations.installer = nixos-raspberrypi.lib.nixosInstaller {
          inherit nixpkgs;
          specialArgs = inputs // {inherit inputs;};
          modules = [self.modules.nixos.installer];
        };
      };
    };
}
