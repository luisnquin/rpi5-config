{inputs, ...}: {
  flake.modules.nixos.wifi = {config, ...}: {
    imports = [inputs.agenix.nixosModules.default];

    age.secrets.wifi.file = ../../../secrets/wifi.env.age;

    # Fallback only: the Pi runs on ethernet, whose auto profile wins the
    # default route; wifi is too slow for chi uploads through the tunnel.
    networking.networkmanager.ensureProfiles = {
      environmentFiles = [config.age.secrets.wifi.path];
      profiles.home-wifi = {
        connection = {
          id = "home-wifi";
          type = "wifi";
        };
        wifi = {
          mode = "infrastructure";
          ssid = "$WIFI_SSID";
        };
        wifi-security = {
          key-mgmt = "wpa-psk";
          psk = "$WIFI_PSK";
        };
        ipv4.method = "auto";
        ipv6.method = "auto";
      };
    };
  };
}
