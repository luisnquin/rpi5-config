{...}: {
  flake.modules.homeManager.git = {
    shared.git = {
      enable = true;
      user = {
        name = "Luis Quiñones";
        email = "luis@quinones.pro";
      };
    };
  };
}
