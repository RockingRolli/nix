{ config, pkgs, lib, ... }:

# Laptop-class host: imports desktop base + adds mobility/power bits.
# Empty extras for now — populate when first laptop host lands. Candidates:
#   - services.tlp.enable / power-profiles-daemon
#   - hardware.brightnessctl
#   - services.fprintd if your laptop has a fingerprint reader
#   - services.libinput touchpad settings
{
  imports = [ ./desktop.nix ];
}
