{ config, pkgs, lib, ... }:

# Workstation-class host: imports desktop base + adds stationary/heavy bits.
# Empty extras for now — populate when the workstation host lands. Candidates:
#   - hardware.nvidia / hardware.amdgpu config
#   - hardware.graphics.enable + 32-bit support for gaming
#   - multi-monitor display manager settings
#   - higher zfs/btrfs ARC limits if running heavier filesystems
{
  imports = [ ./desktop.nix ];
}
