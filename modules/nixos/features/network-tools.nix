{...}: {
  flake.modules.nixos.networkTools = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      inetutils
      iptables
      netcat
      nload
      wirelesstools
    ];
  };
}
