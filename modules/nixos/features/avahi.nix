{...}: {
  flake.modules.nixos.avahi = {
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;

      settings = {
        publish = {
          disable-publishing = false;
          disable-user-service-publishing = true;
          publish-addresses = true;
          publish-workstation = true;
        };

        server.deny-interfaces = [
          "br-*"
          "docker0"
          "tailscale0"
          "veth*"
          "virbr*"
        ];
      };

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
