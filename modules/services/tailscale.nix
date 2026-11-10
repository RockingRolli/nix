{ config, pkgs, lib, ... }:

{
  # Tailscale client. Login is runtime state, not rebuild output: run
  # `sudo tailscale up` once per machine, so no auth key lands in this repo.
  services.tailscale = {
    enable = true;
    # Opens the WireGuard port (UDP 41641) so peers can connect directly
    # instead of through a DERP relay.
    openFirewall = true;
    # "client" lets this machine use subnet routes and exit nodes other
    # devices advertise (`tailscale up --accept-routes`), which is how the
    # home LAN is reached from outside. Also loosens rp_filter, which those
    # routes need.
    useRoutingFeatures = "client";
  };
}
