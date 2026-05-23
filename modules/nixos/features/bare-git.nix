{...}: {
  flake.modules.nixos.bareGit = {
    config,
    lib,
    pkgs,
    ...
  }: let
    createRepo = pkgs.writeShellApplication {
      name = "create";
      runtimeInputs = [pkgs.coreutils pkgs.git pkgs.gnugrep];
      text = ''
        set -euo pipefail

        usage() {
          echo "usage: create <owner>/<project>" >&2
        }

        if [ "$#" -ne 1 ]; then
          usage
          exit 2
        fi

        repo="$1"

        case "$repo" in
          *..* | /* | */*/* | .* | */.* | *.git)
            usage
            exit 2
            ;;
        esac

        if ! printf '%s\n' "$repo" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$'; then
          usage
          exit 2
        fi

        repo_path="/srv/git/$repo.git"

        if [ -e "$repo_path" ]; then
          echo "repository already exists: $repo.git" >&2
          exit 1
        fi

        mkdir -p "$(dirname "$repo_path")"
        git init --bare --initial-branch=main "$repo_path"
        echo "created: $repo.git"
      '';
    };

    listRepos = pkgs.writeShellApplication {
      name = "list";
      runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.gnused];
      text = ''
        set -euo pipefail

        find /srv/git -mindepth 2 -maxdepth 2 -type d -name '*.git' \
          | sed 's#^/srv/git/##; s#\.git$##' \
          | sort
      '';
    };

    helpCommand = pkgs.writeShellApplication {
      name = "help";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        cat <<'EOF'
        available commands:
          create <owner>/<project>  create bare repository
          new <owner>/<project>     alias for create
          list                      list repositories
          ls                        alias for list
        EOF
      '';
    };
  in {
    shared.git = {
      enable = true;
      user = {
        name = "Chimera Git";
        email = "git@chimera";
      };
    };

    users.groups.git = {};

    users.users.git = {
      isSystemUser = true;
      group = "git";
      home = "/srv/git";
      createHome = true;
      shell = "${pkgs.git}/bin/git-shell";
      openssh.authorizedKeys.keys = config.users.users.luisnquin.openssh.authorizedKeys.keys;
    };

    services.openssh.settings.AllowUsers = lib.mkAfter ["git"];

    system.activationScripts.bareGitShellCommands.text = ''
      rm -rf /srv/git/.git-shell-commands

      if [ -L /srv/git/git-shell-commands ]; then
        rm -f /srv/git/git-shell-commands
      fi

      install -d -o git -g git -m 0755 /srv/git/git-shell-commands
      ln -sfn ${lib.escapeShellArg (lib.getExe createRepo)} /srv/git/git-shell-commands/create
      ln -sfn ${lib.escapeShellArg (lib.getExe createRepo)} /srv/git/git-shell-commands/new
      ln -sfn ${lib.escapeShellArg (lib.getExe listRepos)} /srv/git/git-shell-commands/list
      ln -sfn ${lib.escapeShellArg (lib.getExe listRepos)} /srv/git/git-shell-commands/ls
      ln -sfn ${lib.escapeShellArg (lib.getExe helpCommand)} /srv/git/git-shell-commands/help
      chown -h git:git /srv/git/git-shell-commands/create \
        /srv/git/git-shell-commands/new \
        /srv/git/git-shell-commands/list \
        /srv/git/git-shell-commands/ls \
        /srv/git/git-shell-commands/help
    '';

    systemd.tmpfiles.rules = [
      "d /srv/git 0750 git git -"
      "d /srv/git/git-shell-commands 0755 git git -"
    ];
  };
}
