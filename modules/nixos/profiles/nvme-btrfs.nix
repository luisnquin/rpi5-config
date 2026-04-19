{inputs, ...}: {
  flake.modules.nixos.nvmeBtrfs = {
    imports = [
      inputs.self.modules.nixos.diskoNvmeBtrfs
    ];
  };
}
