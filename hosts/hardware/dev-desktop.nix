{ config, lib, modulesPath, ... }:

# PLACEHOLDER hardware configuration. Replaced at install time with the
# output of `nixos-generate-config` on the target VM. Bootloader config
# lives in ../dev-desktop.nix (the host file), NOT here — `nixos-generate-config`
# does not emit boot.loader settings, so keeping them here would mean
# losing them when this file is regenerated.
#
# Regenerate during install:
#   sudo nixos-generate-config --root /mnt --dir /tmp/cfg
#   cp /tmp/cfg/hardware-configuration.nix hosts/hardware/dev-desktop.nix
#
# Or via nixos-anywhere from your laptop:
#   nix run github:nix-community/nixos-anywhere -- \
#     --generate-hardware-config nixos-generate-config hosts/hardware/dev-desktop.nix \
#     --flake .#dev-desktop root@<vm-ip>

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
