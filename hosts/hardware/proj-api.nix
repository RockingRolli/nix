{ config, lib, modulesPath, ... }:

# PLACEHOLDER hardware configuration.
#
# Regenerate this on the target VM during first install:
#   sudo nixos-generate-config --root /mnt --dir /tmp/cfg
#   cp /tmp/cfg/hardware-configuration.nix hosts/hardware/proj-api.nix
#
# Or, with nixos-anywhere:
#   nix run github:nix-community/nixos-anywhere -- \
#     --generate-hardware-config nixos-generate-config hosts/hardware/proj-api.nix \
#     --flake .#proj-api root@<vm-ip>

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
