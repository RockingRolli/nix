{ config, pkgs, lib, ... }:

# System-side desktop: niri compositor + DMS panel/shell + greetd autologin.
# Uses the nixpkgs path per DMS docs (https://danklinux.com/docs/dankmaterialshell/nixos):
# nixpkgs ships both programs.niri and programs.dms-shell as first-class options
# in 26.05. DMS owns ~/.config/niri/* as user-mutable state — populated once per
# VM via `dms setup niri` (interactive TUI) after install.
{
  programs.niri.enable = true;

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

  # Note: xdg.portal.config.niri.default is already set by nixpkgs's own
  # programs/wayland/niri.nix (to "gnome;gtk"). We do not override it here;
  # the base portal module in ../desktop.nix enables xdg-desktop-portal.

  # greetd autologin via initial_session: greetd itself runs the PAM session
  # opening for rvo without prompting, then execs niri-session. This is the
  # documented greetd autologin pattern (tuigreet 0.9.1 has no --autologin
  # flag). default_session below is tuigreet for any subsequent login (e.g.,
  # after logout). To require a password on boot too, delete the
  # initial_session block; greetd will fall through to default_session.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
      initial_session = {
        command = "niri-session";
        user = "rvo";
      };
    };
  };
}
