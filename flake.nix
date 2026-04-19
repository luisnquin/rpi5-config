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

        flake.nixosConfigurations.ryx = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs // {inherit inputs;};
          modules = [
            disko.nixosModules.disko
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
            self.modules.nixos.ryx
          ];
        };
      };
    };
}
