let
  luisnquin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIXW6vsDRgI/AiOdGnQOTyiz1uLFL0o66u0Ahcw9VWyd luis@quinones.pro";
  chimera = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL9xH4LrR9K3lTDtFN4Rysi33AungKN3w2YgjquBDmz3 root@chimera";
in {
  "wifi.env.age".publicKeys = [luisnquin chimera];
  "cloudflared-chimera.age".publicKeys = [luisnquin chimera];
  "pavlov-pin.age".publicKeys = [luisnquin chimera];
}
