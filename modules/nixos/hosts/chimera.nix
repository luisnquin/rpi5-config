{inputs, ...}: {
  flake.modules.nixos.chimera = {
    imports = with inputs.self.modules.nixos; [
      base
      fireflyIii
      nvmeBtrfs
      raspberryPi5
    ];
  };
}
