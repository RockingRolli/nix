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
  # home/openclaw.nix). Keep port and CIDR in sync with that file. This is the
  # subnet the box actually sits on — `openclaw gateway status` reports the
  # dashboard at 192.168.178.153. It was originally guessed as 10.0.0.0/24 from
  # the ollama address in home/openclaw.nix — but ollama lives on a different
  # network the box only routes to, so that guess opened the port to nobody.
  gatewayPort = 18789;
  lanCidr = "192.168.178.0/24";
in

{
  # nix-openclaw is not in nixpkgs: openclaw and its bundled tools only exist
  # via this overlay. home-manager.useGlobalPkgs = true (flake.nix) means the
  # HM module reads this same pkgs, so the overlay must be applied system-wide.
  nixpkgs.overlays = [ nix-openclaw.overlays.default ];

  # Load-bearing, not convenience packages. OpenClaw 2026.9.x resolves its
  # infrastructure binaries — openssl, ffmpeg, ffprobe — through a resolver
  # that deliberately ignores PATH and only accepts a fixed set of OS-managed
  # directories, to block PATH-hijacking. On Linux that set is /usr/bin, /bin,
  # /usr/sbin, /sbin, /run/current-system/sw/bin and /snap/bin, so on NixOS the
  # system profile is the only entry that can be populated — and
  # environment.systemPackages is the only thing that puts a binary there.
  # Nothing in the nix-openclaw wrapper's PATH counts.
  #
  #   - openssl: the gateway generates its TLS cert at startup. Missing, it
  #     throws "openssl not found in trusted system directories" and never
  #     opens its port. Also makes the `openssl rand -hex 32` secret setup
  #     documented below runnable on the box in the first place.
  #   - ffmpeg (ships ffprobe): OpenClaw's own media probe throws the same way
  #     on inbound attachments. Separate from the ffmpeg inside the transcribe
  #     wrapper in home/openclaw.nix, which is a private runtime input.
  #
  # The resolver only checks the path is executable and does not resolve
  # symlinks, so the system-profile symlink into /nix/store is accepted as-is.
  environment.systemPackages = [
    pkgs.openssl
    pkgs.ffmpeg
  ];

  # No binary cache for openclaw. This used to declare cache.garnix.io with its
  # key; nix-openclaw retired that cache and the host no longer resolves at all
  # (NXDOMAIN), so it was a dead substituter every rebuild had to time out on.
  # Consequence: the gateway is a pnpm/node build compiled locally, so the
  # first rebuild after a version bump is slow. If upstream publishes a new
  # cache, its substituter and key go here — a non-trusted flake consumer does
  # not inherit them from nix-openclaw's own nixConfig.

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
