{ config, pkgs, lib, ... }:

{
  # Default container runtime, imported by every host that hasn't opted into
  # docker.nix instead. The two are mutually exclusive — both own the `docker`
  # CLI and daemon socket — so a host imports exactly one. dockerCompat gives
  # projects a working `docker` command + socket without installing Docker.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  users.users.rvo.extraGroups = [ "podman" ];
}
