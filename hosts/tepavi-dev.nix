{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/tepavi-dev.nix
    ../modules/base.nix
    # No services. Add ../modules/services/code-server.nix here to flip this
    # host into a frontend dev box.
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "tepavi-dev";

  home-manager.users.rvo.imports = [ ../home/common.nix ];

  system.stateVersion = "26.05";
}
