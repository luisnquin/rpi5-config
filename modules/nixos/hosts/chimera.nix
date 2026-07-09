{inputs, ...}: {
  flake.modules.nixos.chimera = {
    imports = with inputs.self.modules.nixos; [
      base
      nvmeBtrfs
      raspberryPi5
    ];
  };
}
