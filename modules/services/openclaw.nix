{ config, pkgs, lib, nix-openclaw, ... }:

# System-side half of the OpenClaw host. The agent itself is user-scoped and
# lives in home/openclaw.nix — this module only provides what home-manager
# cannot do from inside the user session: the overlay, the binary cache,
# lingering, the secrets directory, and the firewall hole.
#
# Why the gateway runs as rvo (home-manager) and not as a system service:
# nix-openclaw also ships `nixosModules.openclaw-gateway`, but that module is
# bare — a systemd unit around `openclaw gateway` and nothing else. Plugin
# wiring, skill directories, workspace bootstrap and the tool PATH wrapper all
# live in the home-manager module, which upstream calls the "golden path".
# Running as rvo also means the agent's tools see the same dev environment the
# user has (nix-ld, docker group, ssh keys), which is the whole point here.

let
  # The gateway is reachable from the LAN (gateway.bind = "lan" in
  # home/openclaw.nix). Keep port and CIDR in sync with that file; the CIDR is
  # inferred from the ollama box at 10.0.0.234 and is the one line to change if
  # the network is not a /24.
  gatewayPort = 18789;
  lanCidr = "10.0.0.0/24";
in

{
  # nix-openclaw is not in nixpkgs: openclaw and its bundled tools only exist
  # via this overlay. home-manager.useGlobalPkgs = true (flake.nix) means the
  # HM module reads this same pkgs, so the overlay must be applied system-wide.
  nixpkgs.overlays = [ nix-openclaw.overlays.default ];

  # OpenClaw is a pnpm/node build; without a cache a rebuild compiles the whole
  # gateway locally. garnix is upstream's own CI cache (the keys come from
  # nix-openclaw's flake nixConfig, which a non-trusted flake consumer does not
  # get automatically — hence declaring them here). extra-* so the nixpkgs
  # cache is kept rather than replaced.
  nix.settings = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
  };

  # The gateway is a systemd *user* service. Without lingering it would only
  # run while rvo has a login session open, i.e. the bot would go silent when
  # the ssh session ends and would not come back after a reboot.
  users.users.rvo.linger = true;

  # Secrets are runtime files, never nix store paths — same stance as passwords
  # in modules/base.nix. This module owns the directory; the contents are
  # created out of band (see docs in home/openclaw.nix) and survive rebuilds.
  systemd.tmpfiles.rules = [
    "d /var/lib/openclaw-secrets 0700 rvo users - -"
  ];

  # The gateway listens on the LAN address, so the port has to be opened — but
  # only to the LAN. This is an agent that runs shell commands on request, so
  # the blast radius of a stray route or a port-forward is the whole box; the
  # gateway's own token auth is the second lock, not the first.
  #
  # extraCommands rather than allowedTCPPorts because that option cannot
  # express a source restriction. It is iptables-only, which is what the NixOS
  # firewall uses by default here (nftables is opt-in and interacts badly with
  # docker); IPv6 is deliberately not opened.
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw -p tcp -s ${lanCidr} --dport ${toString gatewayPort} -j nixos-fw-accept
  '';
}
