{inputs, ...}: {
  flake.modules.nixos.chimera = {
    imports = with inputs.self.modules.nixos; [
      base
      farm
      nvmeBtrfs
      raspberryPi5
      skinner
      wifi
    ];
  };
}
