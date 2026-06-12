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

  # greetd autologin via initial_session: greetd itself runs the PAM session
  # opening for rvo without prompting, then execs niri-session. This is the
  # documented greetd autologin pattern (tuigreet 0.9.1 has no --autologin
  # flag). default_session below is tuigreet for any subsequent login (e.g.,
  # after logout). To require a password on boot too, delete the
  # initial_session block; greetd will fall through to default_session.
  services.greetd = {
    enable = true;
    settings = {
      # tuigreet does PAM login on subsequent prompts (after logout or if
      # initial_session ever fails). User sees a real password prompt here.
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd niri-session";
        user = "greeter";
      };
      # First-boot autologin: greetd itself does PAM auth for rvo without
      # prompting, then exec niri-session. This is the right place for
      # autologin (tuigreet 0.9.1 has no --autologin flag of its own).
      initial_session = {
        command = "niri-session";
        user = "rvo";
      };
    };
  };
}
