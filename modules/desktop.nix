{ config, pkgs, lib, ... }:

# GUI base module — imported by ./laptop.nix and ./workstation.nix.
# Anything common to "a NixOS host with a display" goes here.
#
# Empty for now — populate when the first GUI host lands. Candidates:
#   - services.xserver.enable / services.displayManager + a session (wayland or x11)
#   - services.pipewire (audio)
#   - fonts.packages with the nerd font tide expects
#   - networking.networkmanager.enable
#   - hardware.bluetooth.enable
{
}
