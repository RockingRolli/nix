{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/proj-api.nix
    ../modules/base.nix
    ../modules/services/code-server.nix
    # For project-level services (postgres, redis, etc.) use podman inside the
    # project repo instead of declaring them at the NixOS layer.
  ];

  boot.loader.grub.enable = true;
  # lib.mkForce needed until hosts/hardware/proj-api.nix placeholder is
  # regenerated at install time (placeholder incorrectly uses /dev/sda).
  boot.loader.grub.device = lib.mkForce "/dev/vda";
  boot.loader.grub.useOSProber = true;

  networking.hostName = "proj-api";

  # Example agenix-wired secret. Disabled by default so the flake evaluates
  # before you have created the .age file.
  #
  # To enable:
  #   1. Put proj-api's ssh_host_ed25519_key.pub into secrets/secrets.nix.
  #   2. Run: nix run github:ryantm/agenix -- -e secrets/example-token.age
  #   3. Uncomment the block below and `nixos-rebuild switch`.
  #   4. The decrypted plaintext appears at config.age.secrets.example-token.path
  #      with mode 0400 owned by root (override with .owner / .group / .mode).
  #
  # age.secrets.example-token = {
  #   file = ../secrets/example-token.age;
  #   owner = "rvo";
  #   group = "users";
  #   mode = "0400";
  # };

  home-manager.users.rvo = import ../home/common.nix;

  system.stateVersion = "26.05";
}
