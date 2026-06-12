{ config, pkgs, lib, niri-flake, ... }:

# Niri compositor at the system level. The user-side niri config (keybinds,
# outputs) lives in home/desktop/niri.nix.
{
  imports = [ niri-flake.nixosModules.niri ];

  programs.niri.enable = true;

  # Use the nixpkgs niri build instead of niri-flake's source-built variant.
  # Avoids eval-time `builtins.fetchGit` calls (needed by niri's Cargo
  # dependencies like pipewire-rs) that block first-install bootstraps where
  # git isn't on PATH yet. nixpkgs niri 26.04 matches niri-flake's niri-stable.
  programs.niri.package = pkgs.niri;

  # Niri prefers the gtk portal. The base portal module is enabled in
  # ../desktop.nix; this adds the niri-specific preference.
  xdg.portal.config.niri.default = [ "gtk" ];

  # greetd uses tuigreet with --autologin so the PAM/logind transition runs
  # cleanly (session 1 → class=user, seat0/tty1 properly assigned). niri
  # gets DRM master and graphical-session.target activates. To require a
  # password later, drop the --autologin flag.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # tuigreet handles the PAM login (even auto), so logind promotes the
        # session from class=greeter to class=user with proper seat0/tty1
        # assignment. niri then gets a real DRM master and graphical-session
        # .target activates (which DMS's systemd unit depends on).
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session --autologin rvo";
        user = "greeter";
      };
    };
  };
}
