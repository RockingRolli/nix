{ config, pkgs, lib, dms, ... }:

# DankMaterialShell at the home-manager layer. dms.homeModules.niri adds
# the niri-side integration glue (recommended in the DMS docs).
{
  imports = [
    dms.homeModules.dank-material-shell
    dms.homeModules.niri
  ];

  programs.dank-material-shell.enable = true;

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
