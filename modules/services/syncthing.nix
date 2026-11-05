{ config, pkgs, lib, ... }:

{
  # Syncs ~/dotfiles between GUI machines via the Syncthing server. Devices and
  # folders are paired by hand in the web UI (http://localhost:8384), so no device
  # IDs land in this public repo. The override options have to be off: they
  # default to true and delete anything not declared here.
  services.syncthing = {
    enable = true;
    user = "rvo";
    group = "users";
    dataDir = "/home/rvo";
    overrideDevices = false;
    overrideFolders = false;
    # Sync and discovery ports. Peers still have to be paired to get anywhere.
    openDefaultPorts = true;
  };
}
