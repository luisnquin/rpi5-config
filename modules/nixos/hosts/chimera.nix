{inputs, ...}: {
  flake.modules.nixos.chimera = {
    imports = with inputs.self.modules.nixos; [
      base
      chi
      farm
      nvmeBtrfs
      pavlov
      raspberryPi5
      skinner
      wifi
    ];

    # A failed EDID read on HDMI replug falls back to 1024x768 on the 1920x1200 monitor.
    boot.kernelParams = ["video=HDMI-A-1:1920x1200@60"];
  };
}
