{ config, pkgs, lib, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;

    enableTCPIP = false;
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1";
    };

    ensureDatabases = [ "rvo" ];
    ensureUsers = [
      {
        name = "rvo";
        ensureDBOwnership = true;
      }
    ];

    authentication = lib.mkOverride 10 ''
      local all all              trust
      host  all all 127.0.0.1/32 trust
      host  all all ::1/128      trust
    '';
  };
}
