{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/dev-desktop.nix
    ../modules/base.nix
    ../modules/desktop.nix
    ../modules/desktop/niri.nix
    ../modules/desktop/vm.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "dev-desktop";

  # GUI host: layer gui.nix on top of common.nix. gui.nix imports
  # ../home/desktop/{niri,dms}.nix internally.
  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/gui.nix
  ];

  system.stateVersion = "26.05";
}
