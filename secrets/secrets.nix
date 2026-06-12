# agenix recipients map.
#
# For each VM, after first install grab its SSH host pubkey:
#   ssh-keyscan -t ed25519 <vm-ip>
# (the line starting `ssh-ed25519`) and paste it below, replacing the
# corresponding `null`. Same for `rvo-laptop` — paste your laptop's
# personal SSH pubkey so you can `agenix -e` from there.
#
# This file is read ONLY by the agenix CLI when encrypting/re-encrypting
# `.age` files. The system itself decrypts at activation using its own
# /etc/ssh/ssh_host_ed25519_key as the age identity, so freshly-provisioned
# VMs can decrypt their secrets on first boot with no key juggling.
#
# Until at least one host pubkey is filled in, this file declares no
# `.age` mappings — agenix won't try to evaluate the placeholders.

let
  # Host pubkeys — replace each `null` with the host's `ssh-ed25519 AAAA...` line.
  proj-api = null;
  tepavi-dev = null;
  dev-desktop = null;

  # Personal SSH pubkey(s) that should also be able to decrypt.
  rvo-laptop = null;

  # Filter out the still-null slots so partially-populated state still works.
  all = builtins.filter (k: k != null) [ proj-api tepavi-dev dev-desktop rvo-laptop ];
in
{
  # Example mapping — uncomment and add real consumers once `all` is non-empty:
  # "example-token.age".publicKeys = all;
}
