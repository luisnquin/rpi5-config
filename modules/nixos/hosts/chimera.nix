{inputs, ...}: {
  flake.modules.nixos.chimera = {
    imports = with inputs.self.modules.nixos; [
      base
      sops
      fireflyIii
      nvmeBtrfs
      raspberryPi5
    ];
  };
}
