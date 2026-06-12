{ config, lib, modulesPath, ... }:

# PLACEHOLDER hardware configuration.
#
# Regenerate on the target VM during first install:
#   sudo nixos-generate-config --root /mnt --dir /tmp/cfg
#   cp /tmp/cfg/hardware-configuration.nix hosts/hardware/dev-desktop.nix
#
# Or via nixos-anywhere from your laptop:
#   nix run github:nix-community/nixos-anywhere -- \
#     --generate-hardware-config nixos-generate-config hosts/hardware/dev-desktop.nix \
#     --flake .#dev-desktop root@<vm-ip>

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
