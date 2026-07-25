{ config, pkgs, lib, ... }:

# ThinkPad T14s Gen4 AMD — bare-metal GUI laptop running the niri desktop.
{
  imports = [
    ./hardware/laptop.nix
    ../modules/base.nix
    ../modules/virtualisation/podman.nix
    ../modules/laptop.nix          # desktop.nix + power/firmware/mobility bits
    ../modules/performance.nix     # zram + build scheduling
    ../modules/desktop/niri.nix
    # ../modules/gaming.nix          # steam + proton-ge + gamescope/gamemode
    # note: NOT ../modules/desktop/vm.nix — this is bare metal, not a guest.
  ];

  # UEFI systemd-boot. hardware/laptop.nix has an EFI /boot (vfat) and LUKS
  # root; no grub device, so systemd-boot is the natural fit.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # LUKS tuning for the root device. Lives here rather than in
  # hosts/hardware/laptop.nix (which declares the same device) because that
  # file is overwritten by nixos-generate-config; same reasoning as the
  # bootloader settings above.
  #
  # allowDiscards: dm-crypt swallows TRIM unless told otherwise, so without it
  # the enabled fstrim.timer is a no-op for everything on this disk and the SSD
  # slowly fills with blocks it believes are live. The accepted cost is that
  # someone with physical access to the powered-off disk can see which blocks
  # are unused (roughly, how full the filesystem is) — it does not weaken the
  # encryption of the data itself.
  #
  # bypassWorkqueues: skips dm-crypt's per-CPU en/decrypt queues and does the
  # crypto inline. On NVMe those queues are pure latency; upstream recommends
  # bypassing them for SSDs.
  boot.initrd.luks.devices."luks-f9683746-2bd8-457b-8b2b-cce6151aebfe" = {
    allowDiscards = true;
    bypassWorkqueues = true;
  };

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
