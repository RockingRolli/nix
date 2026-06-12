{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/proj-web.nix
    ../modules/base.nix
    # No code-server, no postgres. Add ../modules/code-server.nix here
    # to flip this host into a frontend dev box.
  ];

  networking.hostName = "proj-web";

  system.stateVersion = "26.05";
}
