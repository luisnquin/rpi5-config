{inputs, ...}: {
  flake.modules.homeManager.terminal = {
    imports = with inputs.self.modules.homeManager; [
      cli
      git
      user
    ];
  };
}
