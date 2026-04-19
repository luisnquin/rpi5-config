{...}: {
  home = {
    username = "luisnquin";
    homeDirectory = "/home/luisnquin";
    stateVersion = "26.05";
    enableNixpkgsReleaseCheck = true;
  };

  shared = {
    bat.enable = true;
    btop.enable = true;
    direnv.enable = true;
    eza.enable = true;
    fzf.enable = true;
    git = {
      enable = true;
      user = {
        name = "Luis Quiñones";
        email = "luis@quinones.pro";
      };
    };
    lazygit.enable = true;
    macchina.enable = true;
    magic-wormhole.enable = true;
    starship.enable = true;
    tmux.enable = true;
    zoxide.enable = true;
    zsh.enable = true;
  };
}
