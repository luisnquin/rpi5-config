{inputs, ...}: {
  flake.modules.homeManager.luisnquin = {
    imports = with inputs.self.modules.homeManager; [
      terminal
    ];
  };
}
