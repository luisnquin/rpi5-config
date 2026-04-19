{...}: {
  flake.modules.homeManager.user = {
    home = {
      username = "luisnquin";
      homeDirectory = "/home/luisnquin";
      stateVersion = "26.05";
      enableNixpkgsReleaseCheck = true;
    };
  };
}
