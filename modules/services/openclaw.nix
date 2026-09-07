{ config, pkgs, lib, nix-openclaw, ... }:

# System-side half of the OpenClaw host. The agent itself is user-scoped and
# lives in home/openclaw.nix — this module only provides the four things
# home-manager cannot do from inside the user session.
#
# Why the gateway runs as rvo (home-manager) and not as a system service:
# nix-openclaw also ships `nixosModules.openclaw-gateway`, but that module is
# bare — a systemd unit around `openclaw gateway` and nothing else. Plugin
# wiring, skill directories, workspace bootstrap and the tool PATH wrapper all
# live in the home-manager module, which upstream calls the "golden path".
# Running as rvo also means the agent's tools see the same dev environment the
# user has (nix-ld, docker group, ssh keys), which is the whole point here.

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

  # No firewall hole: the gateway binds loopback (gateway.bind = "loopback").
  # Reach the control UI with `ssh -L 18789:localhost:18789 openclaw`.
}
