# agenix recipients map.
#
# For each VM, after first install grab its SSH host pubkey:
#   ssh-keyscan -t ed25519 <vm-ip>
# (the line starting `ssh-ed25519`) and paste it below.
#
# This file is read ONLY by the agenix CLI when encrypting/re-encrypting
# `.age` files. The system itself decrypts at activation using its own
# /etc/ssh/ssh_host_ed25519_key as the age identity, so freshly-provisioned
# VMs can decrypt their secrets on first boot with no key juggling.

let
  proj-api = "ssh-ed25519 AAAA__REPLACE_WITH_proj-api_HOST_KEY__";
  tepavi-dev = "ssh-ed25519 AAAA__REPLACE_WITH_tepavi-dev_HOST_KEY__";

  # Personal age/SSH keys that should also be able to decrypt (so you can
  # `agenix -e` from your laptop). Add your laptop's SSH pubkey here.
  rvo-laptop = "ssh-ed25519 AAAA__REPLACE_WITH_LAPTOP_KEY__";

  all = [ proj-api tepavi-dev rvo-laptop ];
in
{
  "example-token.age".publicKeys = all;
}
