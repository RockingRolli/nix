{ config, pkgs, lib, ... }:

{
  # Bound to localhost only. Access from your laptop via SSH local forward:
  #   ssh -L 4444:localhost:4444 rvo@<vm-host>
  # then open http://localhost:4444.
  services.code-server = {
    enable = true;
    host = "127.0.0.1";
    port = 4444;
    auth = "none";
    user = "rvo";
    extraPackages = with pkgs; [ git nodejs_22 ];
    # If you flip auth to "password", source the password from agenix:
    #   hashedPasswordFile = config.age.secrets.code-server-password.path;
  };
}
