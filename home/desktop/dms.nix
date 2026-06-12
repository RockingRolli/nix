{ config, pkgs, lib, dms, ... }:

# DankMaterialShell at the home-manager layer. dms.homeModules.niri adds
# the niri-side integration glue (recommended in the DMS docs).
{
  imports = [
    dms.homeModules.dank-material-shell
    dms.homeModules.niri
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
}
