{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/tepavi-dev.nix
    ../modules/base.nix
  ];
  
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "tepavi-dev";

  home-manager.users.rvo.imports = [
    ../home/common.nix
  ];

  system.stateVersion = "26.05";
}
