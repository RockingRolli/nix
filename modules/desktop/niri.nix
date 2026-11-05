{ config, pkgs, lib, dfiles, ... }:

# System-side desktop: niri compositor + DMS panel/shell + greetd login.
# Uses the nixpkgs path per DMS docs (https://danklinux.com/docs/dankmaterialshell/nixos):
# nixpkgs ships both programs.niri and programs.dux-shell as first-class options.
# DMS owns ~/.config/niri/* as user-mutable state — populated once per
# VM via `dms setup niri` (interactive TUI) after install.
#
# Dank Linux was renamed to Dux Labs in 26.11 (shell/greeter v2.0.0): the
# options and packages are dux-*, but the `dms` binary, the dms.service user
# unit and the dms-greeter system user kept their names — hence the mix below.
let
  # NixOS units get a minimal PATH, and the resident Dux apps resolve everything
  # they launch (mpv, ghostty, pkexec, xdg-open, qs) from it. Without these,
  # opening a file from the resident instance fails.
  duxServicePath = [
    "/run/wrappers"
    "/etc/profiles/per-user/rvo"
    "/run/current-system/sw"
  ];
in
{
  imports = [ dfiles.nixosModules.dux-files ];

  programs.niri.enable = true;

  # (The libdisplay-info 0.3.0 overlay that used to live here is gone: nixpkgs
  # now ships a separate `libdisplay-info_0_3` package and niri's derivation
  # takes that instead of the top-level `libdisplay-info`, so the override
  # argument no longer exists and the pin is unnecessary.)

  environment.systemPackages = with pkgs; [
    xwayland-satellite
    dux-calendar
    gnome-text-editor

    # VA-API encode wedges WebRTC on this VCN (remote sees a frozen frame after a
    # minute); repeat the wrapper's own disables since Chromium keeps only the last.
    (brave.override {
      commandLineArgs =
        "--disable-features=AcceleratedVideoEncoder,OutdatedBuildDetector,UseChromeOSDirectVideoDecoder";
    })
  ];

  programs.dux-shell = {
    enable = true;
    systemd = {
      enable = true;
      restartIfChanged = true;
    };
  };

  # File manager and file-chooser backend.
  programs.dux-files = {
    enable = true;
    systemd.enable = true;
    portal.enable = true;
  };

  systemd.user.services.dfiles.path = duxServicePath;

  # useNautilus would register Nautilus's org.freedesktop.FileManager1 activation
  # file, which competes with dfiles for "show in folder". Turning it off makes
  # nixpkgs set FileChooser = "gtk", hence the mkForce rather than the module's
  # portal.preferred.
  programs.niri.useNautilus = false;
  xdg.portal.config.niri."org.freedesktop.impl.portal.FileChooser" = lib.mkForce "dfiles";

  # Folders and remote locations open in Dux Files. Set system-wide
  # (/etc/xdg/mimeapps.list) because ~/.config/mimeapps.list is hand-maintained
  # and still wins over this. Archives are left out: Dux Files is the only
  # handler installed, so it is picked anyway.
  xdg.mime.defaultApplications = lib.genAttrs [
    "inode/directory"
    "x-scheme-handler/trash"
    "x-scheme-handler/sftp"
    "x-scheme-handler/smb"
  ] (_: "dev.duxlabs.files.desktop") // lib.genAttrs [
    # Markdown needs its own entry: the Dux Shell notepad claims it directly.
    "text/plain"
    "text/markdown"
  ] (_: "org.gnome.TextEditor.desktop");

  # Calendar. nixpkgs has the package but no module, so wire the unit it ships
  # by hand. Resident because reminders and sync only run while the daemon does.
  systemd.packages = [ pkgs.dux-calendar ];
  systemd.user.services.dcal = {
    wantedBy = [ "graphical-session.target" ];
    path = duxServicePath;
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
  services.displayManager.dux-greeter = {
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
