{ config, pkgs, lib, ... }:

# GUI-only home-manager content (terminal + theming). Imported by GUI hosts
# (dev-desktop and future laptop/workstation) on top of ./common.nix.
# Compositor (niri) and shell (DMS) are configured at the system level in
# ../modules/desktop/niri.nix per DMS docs; per-user niri config lives in
# ~/.config/niri/dms/*.kdl after the one-time `dms setup niri` step.
{
  # Wayland-native terminal. Minimal config; iterate as desired.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=11";
        pad = "8x8";
        dpi-aware = "yes";
      };
      cursor.style = "beam";
      colors.alpha = 0.95;
    };
  };

  # GPU-accelerated terminal. Kept alongside foot — pick whichever feels
  # right per-session. Minimal config; iterate as desired.
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
      background-opacity = 0.95;
    };
  };

  # GTK theming. Apps following xdg-desktop-portal honour these.
  gtk = {
    enable = true;
    cursorTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3";
    };
  };

  # Qt apps follow the GTK theme so foot, niri prompts, etc., look
  # consistent.
  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  fonts.fontconfig.enable = true;
}
