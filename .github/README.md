# RPI5

## Install

```sh
$ nix build .#nixosConfigurations.installer.config.system.build.sdImage
$ zstd -dc result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
# boot the Pi from the SD with ethernet; root takes the keys in identity
$ nix run nixpkgs#nixos-anywhere -- --flake .#chimera --build-on remote --target-host root@nixos-installer.local
```

nixos-anywhere wipes the NVMe (disko). The new host key breaks the wifi secret: put it in `secrets/secrets.nix` and in identity, then `agenix -r`.

## Rebuild

```sh
$ nixos-rebuild switch --flake .#chimera --build-host chimera --target-host chimera --sudo --ask-sudo-password
```

Builds on the Pi. The `chimera` host (port 998; 22 is endlessh) comes from nyx's ssh config.

## Secrets

```sh
$ cd secrets && nix run github:ryantm/agenix -- -e wifi.env.age
```
