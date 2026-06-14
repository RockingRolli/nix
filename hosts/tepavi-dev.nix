{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/tepavi-dev.nix
    ../modules/base.nix
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "tepavi-dev";

  # GUI host: layer gui.nix on top of common.nix. (Compositor config itself
  # lives on the system side in modules/desktop/niri.nix + programs.dms-shell;
  # gui.nix is just the user-side theming/foot setup.)
  home-manager.users.rvo.imports = [
    ../home/common.nix
  ];

  system.stateVersion = "26.05";
}
