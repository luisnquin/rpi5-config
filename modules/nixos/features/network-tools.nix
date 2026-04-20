{...}: {
  flake.modules.nixos.networkTools = {pkgs, ...}: {
    networking.useDHCP = false;
    networking.dhcpcd.enable = false;
    networking.networkmanager = {
      enable = true;
      dns = "systemd-resolved";
      unmanaged = ["interface-name:tailscale*"];
    };

    services.resolved.enable = true;

    environment.systemPackages = with pkgs; [
      inetutils
      iptables
      netcat
      nload
      wirelesstools
    ];
  };
}
