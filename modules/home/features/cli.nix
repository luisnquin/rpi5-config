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
      tmux = {
        enable = true;
        status = {
          ssh.enable = false;
          gpg.enable = false;
          lsyncd.enable = false;
          gitmux.enable = false;
        };
      };
      zoxide.enable = true;
      zsh.enable = true;
    };
  };
}
