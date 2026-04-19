{inputs, ...}: {
  flake.modules.nixos.ryx = {
    imports = with inputs.self.modules.nixos; [
      base
      nvmeBtrfs
      raspberryPi5
    ];
  };
}
