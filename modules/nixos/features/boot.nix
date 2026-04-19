{...}: {
  flake.modules.nixos.boot = {
    boot.loader.raspberry-pi.bootloader = "kernel";
    boot.tmp.useTmpfs = true;
  };
}
