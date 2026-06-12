{ config, pkgs, lib, dms, ... }:

# DankMaterialShell at the home-manager layer.
# Note: dms.homeModules.niri is NOT imported here — it depends on
# niri-flake's programs.niri.settings/config.lib.niri.actions which are
# not available on the nixpkgs path. DMS niri keybind integration is
# managed via `dms setup niri` (interactive TUI) instead.
{
  imports = [
    dms.homeModules.dank-material-shell
  ];

  programs.dank-material-shell = {
    enable = true;
    # Generate ~/.config/systemd/user/dms.service with WantedBy = graphical-session.target.
    # Without this, niri runs to a blank surface because DMS never launches.
    systemd.enable = true;
  };
  # Use nixpkgs quickshell (0.3.0) instead of the DMS default which builds
  # from source via builtins.fetchGit — that fetch runs at eval time and
  # breaks bootstrapping on machines where git is not yet installed.
  # Upstream docs explicitly say 0.3.0 (the nixpkgs version) is sufficient.
  programs.dank-material-shell.quickshell.package = pkgs.quickshell;

  # Feature flags default to true and pull in their respective tools:
  #   enableSystemMonitoring -> dgop
  #   enableVPN              -> nm-applet equivalents
  #   enableDynamicTheming   -> matugen
  #   enableAudioWavelength  -> cava
  #   enableCalendarEvents   -> khal
  #   enableClipboardPaste   -> wtype
  # Disable individual ones here if the panel doesn't use them, to keep
  # the closure smaller. Defaults are fine for first boot.

  # DMS's nix module writes ~/.config/niri/config.kdl with include statements
  # for dms/*.kdl fragments, but the fragment files themselves are written by
  # `dms setup niri` (TUI run once at install time). Without them, niri refuses
  # to start because the includes fail.
  #
  # Seed empty placeholders so niri's includes resolve. DMS's deployer treats
  # zero-byte files as "deploy needed" and will fill them with real content on
  # first run; once content is present, the placeholder logic doesn't fire
  # again (the test below skips files that already exist).
  home.activation.dmsSeedNiriFragments = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.config/niri/dms"
    for f in alttab binds colors layout outputs wpblur cursor windowrules; do
      [ -e "$HOME/.config/niri/dms/$f.kdl" ] || touch "$HOME/.config/niri/dms/$f.kdl"
    done
  '';
}
