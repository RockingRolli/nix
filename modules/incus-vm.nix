{ lib, modulesPath, ... }:

# Guest side of an Incus VM. nixpkgs' incus-virtual-machine profile fixes the
# disk layout (by-label root + ESP), bootloader and incus-agent, so Incus
# hosts need no hardware-configuration file. The upstream images:nixos/* VM
# images are built from the same profile: launch one, then switch it to the
# host config (raiser: `task vm:nixos-bootstrap HOST=<host>`). After that the
# VM updates like any other host (nh / nixos-rebuild).

{
  imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];

  # The profile allows passwordless root login on the console (meant for
  # throwaway images). Access is via the SSH keys from base.nix instead.
  users.users.root.initialHashedPassword = lib.mkForce "!";

  # Identify to DHCP by MAC instead of dhcpcd's DUID, which is generated on
  # first boot: a recreated VM keeps its MAC (pinned in raiser's tofu/) and
  # thereby its lease/reservation.
  networking.dhcpcd.extraConfig = "clientid";

  # The profile pulls in profiles/minimal.nix; man pages and fish completions
  # are worth having on a dev box.
  documentation.man.enable = true;
  programs.fish.generateCompletions = true;
}
