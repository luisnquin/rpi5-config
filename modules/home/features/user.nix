{...}: {
  flake.modules.homeManager.user = {
    home = {
      username = "luisnquin";
      homeDirectory = "/home/luisnquin";
      stateVersion = "25.11";
      enableNixpkgsReleaseCheck = true;
    };
  };
}
