# RPI5

## Setup

```sh
$ git clone git@github.com:nvmd/nixos-raspberrypi.git && cd nixos-raspberrypi
# append your public key to users.users.*.openssh.authorizedKeys.keys before building
$ nix build .#installerImages.rpi5
# insert SD card
$ zstd -dc ./result/sd-image/*.img.zst | sudo dd of=/dev/sda bs=4M status=progress conv=fsync
# move SD to RPI5, power on, connect via ethernet
$ nix run nixpkgs#nixos-anywhere -- --no-substitute-on-destination --build-on local --flake .#chimera --target-host root@<address>

# wait for install, then disconnect, remove SD and power on again
```

After those steps  you should connect via SSH and set up your password.

## Rebuild

```sh
# clue: tailscale
$ nixos-rebuild switch --flake .#chimera --target-host root@chimera
```