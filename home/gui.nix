{ config, pkgs, lib, ... }:

# GUI-only home-manager content (terminal + theming). Imported by GUI hosts
# (dev-desktop, desktop-work, laptop) on top of ./common.nix.
# Compositor (niri) and shell (DMS) are configured at the system level in
# ../modules/desktop/niri.nix per DMS docs; per-user niri config lives in
# ~/.config/niri/dms/*.kdl after the one-time `dms setup niri` step.
{
  # GPU-accelerated terminal. Installed as a plain package (not via the HM
  # programs.ghostty module) so ~/.config/ghostty/config stays user-mutable
  # — same pattern as DMS owning ~/.config/niri/*. Edit the config in
  # place and reload, no rebuild needed.
  home.packages = [ pkgs.ghostty ];

  # Video player. auto-safe picks VA-API on the laptop's Radeon 780M (decode
  # on the GPU, easier on the battery) and falls back to software decoding
  # wherever that isn't available, e.g. the dev-desktop VM.
  # Default apps are deliberately not set here: xdg.mimeApps would take over
  # ~/.config/mimeapps.list, which is hand-maintained. mpv is the only video
  # handler installed, so it is picked anyway.
  programs.mpv = {
    enable = true;
    config.hwdec = "auto-safe";
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
    # Dark mode. adw-gtk3 renders its dark variant when apps get this hint;
    # GTK3 apps read it from settings.ini at startup, GTK4/libadwaita
    # honour it too. Paired with the dconf color-scheme below so apps that ask
    # xdg-desktop-portal-gtk for the preference (rather than reading the .ini)
    # also come up dark.
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  # Qt dialogs go through the portal, so file pickers open in Dux Files. The gtk3
  # theme aborts on opening one, because XDG_DATA_DIRS has no GSettings schemas.
  qt = {
    enable = true;
    platformTheme.name = "xdgdesktopportal";
    style.name = "adwaita-dark";
  };

  fonts.fontconfig.enable = true;

  # Separate agent for the Tepavi key, selected per host with IdentityAgent and
  # ForwardAgent in ~/dotfiles/ssh/tepavi. A compromised server then only reaches
  # this key through agent forwarding, not everything in the main agent. Lives
  # here rather than in home/dotfiles.nix so it exists before a machine's links.
  systemd.user.services.ssh-agent-tepavi = {
    Unit.Description = "SSH agent for Tepavi";
    Service.ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a %t/ssh-agent-tepavi.sock";
    Install.WantedBy = [ "default.target" ];
  };
}
