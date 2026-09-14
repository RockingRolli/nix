{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/openclaw.nix
    ../modules/base.nix
    ../modules/virtualisation/docker.nix
    ../modules/services/openclaw.nix
    # Headless: no desktop.nix. The gateway's control UI is a web app served
    # on the LAN address (see modules/services/openclaw.nix), not a local GUI.
  ];

  # Legacy BIOS boot: hardware/openclaw.nix has no EFI /boot partition, so grub
  # writes to the disk's MBR rather than systemd-boot to an ESP.
  #
  # /dev/sda, not the /dev/vda the other VM hosts use: this Proxmox VM is on a
  # VirtIO SCSI controller (virtio_scsi + sd_mod in the initrd modules, no
  # virtio_blk), so the disk is a SCSI device. Confirm with `lsblk` on the box —
  # a wrong device here fails the install of the bootloader, not the build.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "openclaw";

  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/openclaw.nix
  ];

  system.stateVersion = "26.05";
}
