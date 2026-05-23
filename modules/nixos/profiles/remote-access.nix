{inputs, ...}: {
  flake.modules.nixos.remoteAccess = {
    imports = with inputs.self.modules.nixos; [
      bareGit
      endlessh
      fail2ban
      firewall
      networkTools
      openssh
      tailscale
    ];
  };
}
