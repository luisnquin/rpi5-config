{...}: {
  flake.modules.homeManager.cli = {
    shared = {
      bat.enable = true;
      btop.enable = true;
      direnv.enable = true;
      eza.enable = true;
      fzf.enable = true;
      lazygit.enable = true;
      macchina.enable = true;
      magic-wormhole.enable = true;
      starship.enable = true;
      tmux.enable = true;
      zoxide.enable = true;
      zsh.enable = true;
    };
  };
}
