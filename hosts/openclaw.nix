{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/openclaw.nix
    ../modules/base.nix
    ../modules/virtualisation/docker.nix
    ../modules/services/openclaw.nix
    # Headless: no desktop.nix. The gateway has no GUI — the control UI is a
    # web app reached over an ssh tunnel (see modules/services/openclaw.nix).
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "openclaw";

  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/openclaw.nix
  ];

  system.stateVersion = "26.05";
}
