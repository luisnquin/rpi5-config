{
  pkgs,
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.niri.homeModules.niri
  ];

  programs.niri = {
    enable = true;
    settings = {
      input = {
        keyboard.xkb.layout = "us";
        touchpad = {
          tap = true;
          natural-scroll = true;
        };
        mouse.natural-scroll = true;
        warp-mouse-to-focus.enable = true;
        focus-follows-mouse.max-scroll-amount = "0%";
      };

      outputs."HDMI-A-1" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        scale = 1.0;
        position = {
          x = 0;
          y = 0;
        };
      };

      layout = {
        gaps = 8;
        center-focused-column = "on-overflow";
        preset-column-widths = [
          {proportion = 1.0 / 3.0;}
          {proportion = 1.0 / 2.0;}
          {proportion = 2.0 / 3.0;}
          {proportion = 1.0;}
        ];
        default-column-width = {proportion = 0.5;};

        focus-ring = {
          width = 2;
          active = {
            gradient = {
              from = "#89b4fa";
              to = "#cba6f7";
              angle = 45;
            };
          };
          inactive.color = "#45475a";
        };

        shadow = {
          enable = true;
          softness = 20;
          spread = 3;
          offset = {
            x = 0;
            y = 4;
          };
          color = "#00000070";
        };
      };

      spawn-at-startup = [
        {sh = "swww-daemon && swww img ./wallpaper.jpg";}
        {sh = "waybar";}
        {sh = "swaync";}
        {sh = "wl-paste --type text --watch cliphist store";}
      ];

      prefer-no-csd = true;
      screenshot-path = "~/Pictures/Screenshots/Screenshot_%Y-%m-%d_%H-%M-%S.png";

      animations = {
        slowdown = 0.8;
      };

      window-rules = [
        {
          geometry-corner-radius = {
            top-left = 12.0;
            top-right = 12.0;
            bottom-right = 12.0;
            bottom-left = 12.0;
          };
          clip-to-geometry = true;
        }
        {
          matches = [{is-active = false;}];
          opacity = 0.95;
        }
      ];

      binds = let
        screenshot = {screenshot = [];};
        screenshot-screen = {screenshot-screen = [];};
        move-column-to-workspace = index: {move-column-to-workspace = [index];};
      in
        with config.lib.niri.actions; {
          "Mod+Return".action = spawn "ghostty";
          "Mod+D".action = spawn "fuzzel";
          "Mod+Shift+E".action = quit;
          "Mod+Shift+Q".action = close-window;
          "Mod+Alt+L".action = spawn "swaylock";

          "Mod+H".action = focus-column-left;
          "Mod+J".action = focus-window-down;
          "Mod+K".action = focus-window-up;
          "Mod+L".action = focus-column-right;

          "Mod+Shift+H".action = move-column-left;
          "Mod+Shift+J".action = move-window-down;
          "Mod+Shift+K".action = move-window-up;
          "Mod+Shift+L".action = move-column-right;

          "Mod+1".action = focus-workspace 1;
          "Mod+2".action = focus-workspace 2;
          "Mod+3".action = focus-workspace 3;
          "Mod+4".action = focus-workspace 4;
          "Mod+5".action = focus-workspace 5;
          "Mod+6".action = focus-workspace 6;
          "Mod+7".action = focus-workspace 7;
          "Mod+8".action = focus-workspace 8;
          "Mod+9".action = focus-workspace 9;

          "Mod+Shift+1".action = move-column-to-workspace 1;
          "Mod+Shift+2".action = move-column-to-workspace 2;
          "Mod+Shift+3".action = move-column-to-workspace 3;
          "Mod+Shift+4".action = move-column-to-workspace 4;
          "Mod+Shift+5".action = move-column-to-workspace 5;
          "Mod+Shift+6".action = move-column-to-workspace 6;
          "Mod+Shift+7".action = move-column-to-workspace 7;
          "Mod+Shift+8".action = move-column-to-workspace 8;
          "Mod+Shift+9".action = move-column-to-workspace 9;

          "Mod+Comma".action = consume-window-into-column;
          "Mod+Period".action = expel-window-from-column;
          "Mod+R".action = switch-preset-column-width;
          "Mod+F".action = maximize-column;
          "Mod+Shift+F".action = fullscreen-window;
          "Mod+C".action = center-column;

          "XF86AudioRaiseVolume".action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+";
          "XF86AudioLowerVolume".action = spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-";
          "XF86AudioMute".action = spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle";

          "XF86MonBrightnessUp".action = spawn "brightnessctl" "set" "+5%";
          "XF86MonBrightnessDown".action = spawn "brightnessctl" "set" "5%-";

          "Mod+Print".action = screenshot;
          "Print".action = screenshot-screen;
        };
    };
  };

  programs.waybar = {
    enable = true;
    style = ''
      * {
          font-family: "SpaceMono Nerd Font", "JetBrainsMono Nerd Font", monospace;
          font-size: 13px;
          min-height: 0;
      }

      window#waybar {
          background: rgba(30, 30, 46, 0.9);
          color: #cdd6f4;
          border-bottom: 2px solid #89b4fa;
      }

      #workspaces button {
          padding: 0 5px;
          background: transparent;
          color: #cdd6f4;
          border-radius: 0;
      }

      #workspaces button.focused {
          background: #89b4fa;
          color: #1e1e2e;
      }

      #clock, #battery, #cpu, #memory, #wireplumber, #tray, #custom-notifications, #custom-power {
          padding: 0 10px;
      }

      #clock {
          color: #cba6f7;
          font-weight: bold;
      }

      #battery.critical:not(.charging) {
          background-color: #f38ba8;
          color: #1e1e2e;
          animation-name: blink;
          animation-duration: 0.5s;
          animation-timing-function: linear;
          animation-iteration-count: infinite;
          animation-direction: alternate;
      }

      @keyframes blink {
          to {
              background-color: transparent;
          }
      }
    '';
    settings = [
      {
        layer = "top";
        position = "top";
        height = 34;
        spacing = 4;
        modules-left = ["niri/workspaces" "niri/window"];
        modules-center = ["clock"];
        modules-right = ["tray" "cpu" "memory" "wireplumber" "battery" "custom/notifications" "custom/power"];

        "niri/workspaces" = {
          format = "{icon}";
          format-icons = {
            default = "○";
            focused = "●";
          };
        };

        "niri/window" = {
          format = "{}";
          max-length = 50;
        };

        clock = {
          format = "{:%H:%M  |  %a %d %b}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
        };

        cpu = {
          format = " {usage}%";
          tooltip = false;
        };

        memory = {
          format = " {}%";
        };

        wireplumber = {
          format = "{icon} {volume}%";
          format-muted = "";
          on-click = "pavucontrol";
          format-icons = ["" "" ""];
        };

        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-alt = "{icon} {time}";
          format-icons = ["" "" "" "" ""];
        };

        "custom/notifications" = {
          tooltip = false;
          format = "{icon}";
          format-icons = {
            notification = "<span foreground='red'><sup>•</sup></span>";
            none = "";
            dnd-notification = "<span foreground='red'><sup>•</sup></span>";
            dnd-none = "";
            inhibited-notification = "<span foreground='red'><sup>•</sup></span>";
            inhibited-none = "";
            dnd-inhibited-notification = "<span foreground='red'><sup>•</sup></span>";
            dnd-inhibited-none = "";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "custom/power" = {
          format = "⏻";
          tooltip = false;
          on-click = "wlogout";
        };
      }
    ];
  };

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        terminal = "ghostty -e";
        prompt = "❯ ";
        width = 40;
        lines = 10;
        font = "SpaceMono Nerd Font:size=10";
        fields = "name,generic,comment,executable";
        show-actions = "yes";
        layer = "overlay";
        exit-on-keyboard-focus-loss = "yes";
      };
      colors = {
        background = "1e1e2eff";
        text = "cdd6f4ff";
        match = "f38ba8ff";
        selection = "313244ff";
        selection-text = "cdd6f4ff";
        border = "89b4faff";
      };
      border = {
        width = 2;
        radius = 10;
      };
    };
  };

  services.swaync = {
    enable = true;
    settings = {
      style-path = "~/.config/swaync/style.css";
      positionX = "right";
      positionY = "top";
      control-center-width = 380;
      control-center-height = 600;
      notification-window-width = 400;
      widgets = ["title" "dnd" "notifications" "mpris"];
      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear All";
        };
        dnd = {
          text = "Do Not Disturb";
        };
      };
    };
  };

  home.packages = with pkgs; [
    swww
    grim
    slurp
    wl-clipboard
    brightnessctl
    wireplumber
    pavucontrol
    wlogout
    cliphist
  ];
}
