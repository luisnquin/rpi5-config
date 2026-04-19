{...}: {
  flake.modules.nixos.raspberryPiFirmware = {lib, ...}: {
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
