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

  # greetd autologins rvo straight into a niri-session. To require a
  # password later, swap default_session.command for
  # "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd niri-session".
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.niri}/bin/niri-session";
        user = "rvo";
      };
    };
  };
}
