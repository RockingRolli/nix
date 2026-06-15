{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/proj-api.nix
    ../modules/base.nix
    ../modules/virtualisation/podman.nix
    ../modules/services/code-server.nix
    # For project-level services (postgres, redis, etc.) use podman inside the
    # project repo instead of declaring them at the NixOS layer.
  ];

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "proj-api";

  home-manager.users.rvo.imports = [ ../home/common.nix ];

  system.stateVersion = "26.05";
}
