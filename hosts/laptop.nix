{ config, pkgs, lib, ... }:

# ThinkPad T14s Gen4 AMD — bare-metal GUI laptop running the niri desktop.
{
  imports = [
    ./hardware/laptop.nix
    ../modules/base.nix
    ../modules/virtualisation/podman.nix
    ../modules/laptop.nix          # desktop.nix + power/firmware/mobility bits
    ../modules/desktop/niri.nix
    # note: NOT ../modules/desktop/vm.nix — this is bare metal, not a guest.
  ];

  # UEFI systemd-boot. hardware/laptop.nix has an EFI /boot (vfat) and LUKS
  # root; no grub device, so systemd-boot is the natural fit.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Newer kernel for recent AMD Phoenix silicon (GPU/Wi-Fi/power).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "laptop";

  # Real timezone for a mobile host (base.nix defaults to UTC via mkDefault;
  # its `de` console keymap implies Germany).
  time.timeZone = "Europe/Berlin";

  # GUI host: layer gui.nix on top of common.nix. (Compositor + DMS shell are
  # configured system-side in modules/desktop/niri.nix; gui.nix is user-side
  # terminal + theming.)
  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/gui.nix
  ];

  system.stateVersion = "26.05";
}
