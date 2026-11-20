{ config, pkgs, lib, ... }:

# Dev VM on the Incus cluster. Disposable: ~/dev lives on an Incus custom
# volume (attached by raiser's tofu/), everything else comes from this flake.

{
  imports = [
    ../modules/incus-vm.nix
    ../modules/base.nix
    ../modules/virtualisation/podman.nix
  ];

  networking.hostName = "incus-dev";

  home-manager.users.rvo.imports = [ ../home/common.nix ];

  system.stateVersion = "26.05";
}
