{ config, lib, modulesPath, ... }:

# PLACEHOLDER hardware configuration. See hosts/hardware/proj-api.nix for
# how to regenerate this on the target VM.

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
