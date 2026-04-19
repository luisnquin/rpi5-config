{lib, ...}: {
  flake.modules.nixos.raspberryPiFirmware = {
    hardware.raspberry-pi.config = {
      all = {
        options = {
          enable_uart = lib.mkForce {
            enable = false;
            value = false;
          };
          uart_2ndstage = lib.mkForce {
            enable = false;
            value = false;
          };
        };
      };
    };
  };
}
