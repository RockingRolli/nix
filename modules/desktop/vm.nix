{ config, pkgs, lib, ... }:

# Guest-side conveniences. Pixels and input already work without this module
# — virt-manager / Proxmox negotiate SPICE with QEMU on the host side and
# the guest renders to the default virtio-gpu surface. This module adds the
# *conveniences* on top:

{
  # Clipboard host<->guest + dynamic resolution match when virt-viewer/
  # remote-viewer window resizes.
  services.spice-vdagentd.enable = true;

  # qemu-ga socket; lets the hypervisor do graceful shutdowns via libvirt's
  # API and time-sync after host suspend. ACPI shutdown still works without
  # this; qemu-ga is the cooperative path.
  services.qemuGuest.enable = true;
}
