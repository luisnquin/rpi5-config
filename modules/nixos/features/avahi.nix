{...}: {
  flake.modules.nixos.avahi = {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;

      publish = {
        enable = true;
        addresses = true;
        workstation = true;
        userServices = false;
      };

      denyInterfaces = [
        "br-*"
        "docker0"
        "tailscale0"
        "veth*"
        "virbr*"
      ];

      extraServiceFiles.ssh = ''
        <?xml version="1.0" standalone='no'?>
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_ssh._tcp</type>
            <port>998</port>
          </service>
        </service-group>
      '';
    };
  };
}
