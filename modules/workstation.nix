{ config, pkgs, lib, ... }:

# Bare-metal GUI host: desktop base + what real hardware needs regardless of
# form factor. Imported by desktop-work directly and by laptop via ./laptop.nix.
# Because this is real hardware it imports desktop.nix but NOT desktop/vm.nix
# (that module is spice/qemu-guest guest conveniences only relevant inside a
# hypervisor).
{
  imports = [ ./desktop.nix ];

  # Redistributable firmware for the Wi-Fi/Bluetooth combo card and the iGPU.
  hardware.enableRedistributableFirmware = true;

  # GPU acceleration for the iGPU. niri/quickshell render through this; 32-bit
  # support for the occasional 32-bit GL app.
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Power management. power-profiles-daemon (NOT tlp — they conflict, pick one)
  # so the DMS panel's power-profile switch has a backend to talk to.
  services.power-profiles-daemon.enable = true;
  powerManagement.enable = true;

  # Battery percentage / charge state for the DMS panel indicator.
  services.upower.enable = true;

  # LVFS firmware updates (`fwupdmgr refresh && fwupdmgr update`).
  services.fwupd.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
}
