{ config, pkgs, lib, ... }:

# GMKtec NucBox K12 — bare-metal desktop running the same niri setup as laptop.
{
  imports = [
    ./hardware/desktop-work.nix
    ../modules/base.nix
    ../modules/virtualisation/docker.nix   # docker + compose v2 (not podman)
    ../modules/workstation.nix     # desktop.nix + firmware/graphics/bluetooth
    ../modules/performance.nix     # zram + build scheduling
    ../modules/desktop/niri.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  boot.supportedFilesystems = [ "nfs" ];

  networking.hostName = "desktop-work";

  time.timeZone = "Europe/Berlin";

  # GUI host: layer gui.nix on top of common.nix.
  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/gui.nix
  ];

  system.stateVersion = "26.05";
}
