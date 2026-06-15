{ config, pkgs, lib, ... }:

{
  # Opt-in Docker runtime, mutually exclusive with podman.nix — a host imports
  # exactly one. Both runtimes own the `docker` CLI and daemon socket, so
  # importing both is an intentional build-time conflict.
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  # Lets rvo talk to the docker socket without sudo. Trade-off: docker group
  # membership is effectively root — acceptable on a single-user dev VM.
  users.users.rvo.extraGroups = [ "docker" ];

  # Compose v2: provides both `docker compose` and the `docker-compose` shim.
  environment.systemPackages = [ pkgs.docker-compose ];
}
