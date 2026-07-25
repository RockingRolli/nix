{ config, pkgs, lib, ... }:

# Laptop-class host: desktop base + mobility/power/firmware bits for a
# bare-metal ThinkPad (T14s Gen4 AMD, Phoenix / Radeon 780M). Because this is
# real hardware it imports desktop.nix but NOT desktop/vm.nix (that module is
# spice/qemu-guest guest conveniences only relevant inside a hypervisor).
{
  imports = [ ./desktop.nix ];

  # Redistributable firmware for the Wi-Fi/Bluetooth combo card and the iGPU.
  hardware.enableRedistributableFirmware = true;

  # GPU acceleration for the AMD Radeon 780M iGPU. niri/quickshell render
  # through this; 32-bit support for the occasional 32-bit GL app.
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

  # LVFS firmware updates — ThinkPads are well supported here
  # (`fwupdmgr refresh && fwupdmgr update`).
  services.fwupd.enable = true;

  # Bluetooth (Qualcomm combo card).
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # Touchpad: tap-to-click + natural scrolling.
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
    };
  };

  # Fingerprint reader. The T14s Gen4 AMD ships a Goodix sensor; libfprint
  # support is improving but not guaranteed — enrol once after first boot with
  # `fprintd-enroll` and verify. Harmless if the sensor turns out unsupported
  # (fprintd simply finds no device). PAM then accepts fingerprint for
  # sudo/login where configured.
  services.fprintd.enable = true;

  # CLI helpers: backlight control (niri brightness keybinds shell out to
  # brightnessctl) and power debugging.
  environment.systemPackages = with pkgs; [
    brightnessctl
    powertop
  ];
}
