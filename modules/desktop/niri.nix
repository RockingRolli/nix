{ config, pkgs, lib, ... }:

# System-side desktop: niri compositor + DMS panel/shell + greetd login.
# Uses the nixpkgs path per DMS docs (https://danklinux.com/docs/dankmaterialshell/nixos):
# nixpkgs ships both programs.niri and programs.dms-shell as first-class options
# in 26.05. DMS owns ~/.config/niri/* as user-mutable state — populated once per
# VM via `dms setup niri` (interactive TUI) after install.
{
  programs.niri.enable = true;

  # niri 26.04 vendors libdisplay-info-sys 0.3.0, whose build.rs requires
  # `libdisplay-info < 0.4.0`; nixpkgs ships 0.4.0, so the build panics at
  # pkg-config. Scoped to niri via override, leaving 0.4.0 in place for
  # everything else. Drop this once nixpkgs carries a niri that accepts 0.4.0.
  nixpkgs.overlays = [
    (final: prev: {
      niri = prev.niri.override {
        libdisplay-info = prev.libdisplay-info.overrideAttrs (old: {
          version = "0.3.0";
          src = prev.fetchFromGitLab {
            domain = "gitlab.freedesktop.org";
            owner = "emersion";
            repo = "libdisplay-info";
            rev = "0.3.0";
            sha256 = "sha256-nXf2KGovNKvcchlHlzKBkAOeySMJXgxMpbi5z9gLrdc=";
          };
        });
      };
    })
  ];

  environment.systemPackages = with pkgs; [
    xwayland-satellite
    brave
  ];

  programs.dms-shell = {
    enable = true;
    systemd = {
      enable = true;
      restartIfChanged = true;
    };
  };

  # Equivalent of `systemctl --user add-wants niri.service dms` from the DMS
  # Fedora docs: ensures dms.service is started as part of niri's startup
  # chain (after niri exports WAYLAND_DISPLAY etc.) rather than racing in
  # parallel from graphical-session.target activation.
  systemd.user.services.niri.wants = [ "dms.service" ];

  # Keyboard layout for the compositor. niri (via libxkbcommon) reads the
  # layout from XKB_DEFAULT_LAYOUT, NOT from services.xserver.xkb — and greetd
  # doesn't put the console keymap into the session env. Export it here from
  # the single source of truth in base.nix so the GUI keyboard matches the
  # console. niri.service inherits this (niri-session imports the user-manager
  # env at startup). DMS still owns ~/.config/niri, so a layout set there would
  # override this; leaving niri's xkb block empty falls back to this default.
  systemd.user.services.niri.environment.XKB_DEFAULT_LAYOUT =
    config.services.xserver.xkb.layout;

  # Quickshell (spawned by dms.service) is a Qt app:
  # - QT_QPA_PLATFORM=wayland selects the wayland platform plugin (otherwise
  #   Qt defaults to xcb and quickshell would never connect to the compositor).
  # - QT_QPA_PLATFORMTHEME is forcibly unset to suppress the qt6gtk2 platform
  #   theme that home/gui.nix's qt.platformTheme.name="gtk" exports into the
  #   session — qt6gtk2 is X11-linked and crashes on XOpenDisplay in a pure
  #   Wayland service environment.
  systemd.user.services.dms.environment = {
    QT_QPA_PLATFORM = "wayland";
    # The HM qt.platformTheme.name = "gtk" in home/gui.nix exports
    # QT_QPA_PLATFORMTHEME=gtk2 into the niri session, which makes
    # quickshell try to load X11-linked qt6gtk2 and crash on
    # XOpenDisplay. Override to empty so Qt uses the builtin fusion
    # theme (Wayland-safe). lib.mkForce because hm-session-vars
    # exports the value through a different merge channel.
    QT_QPA_PLATFORMTHEME = lib.mkForce "";
  };

  # Note: xdg.portal.config.niri.default is already set by nixpkgs's own
  # programs/wayland/niri.nix (to "gnome;gtk"). We do not override it here;
  # the base portal module in ../desktop.nix enables xdg-desktop-portal.

  # DankGreeter — owns services.greetd itself, so no greetd block here.
  services.displayManager.dms-greeter = {
    enable = true;
    compositor.name = "niri";

    # The greeter's niri runs as dms-greeter and never sees the
    # XKB_DEFAULT_LAYOUT exported above, so set the layout in its own config.
    compositor.customConfig = ''
      input {
          keyboard {
              xkb {
                  layout "${config.services.xserver.xkb.layout}"
              }
          }
      }
    '';

    # Reuse rvo's DMS theme/wallpaper on the login screen.
    configHome = "/home/rvo";
  };
}
