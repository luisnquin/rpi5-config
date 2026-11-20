{inputs, ...}: {
  flake.modules.nixos.nanovu = {config, ...}: let
    listen = "127.0.0.1:4010";
    credential = name: "/run/credentials/nanovu.service/${name}";
    paths = config.age.secrets;
  in {
    imports = [inputs.agenix.nixosModules.default inputs.nanovu.nixosModules.default];

    age.secrets = {
      nanovu-stg-secret-key.file = ../../../secrets/nanovu-stg-secret-key.age;
    };

    services.cloudflared.tunnels."8197aee8-115d-4af3-abaa-bbd9ae1fb596".ingress."nanovu.nshard.com" = "http://${listen}";

    services.nanovu = {
      enable = true;
      credentials = {
        stg-secret-key = paths.nanovu-stg-secret-key.path;
      };
      settings = {
        inherit listen;
        # gate-k9 dev and staging share one Novu environment.
        environments.stg = {
          application_identifier = "O-yUn9zOb_Gl";
          secret_key_file = credential "stg-secret-key";
          bridge_hosts = ["api.nshard.com" "staging-gate-k9-mzni.encr.app"];
        };
      };
    };
  };
}
