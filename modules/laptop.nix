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

  # Cap charging at 80%. A lithium cell held at full charge ages markedly
  # faster than one parked around 80, and a dev laptop spends most of its life
  # on AC — so the runtime traded away is mostly runtime that never gets used.
  # start=75 gives a 5-point hysteresis band; without it the EC trickle-charges
  # continuously at the threshold, which is its own kind of wear.
  #
  # There is no upstream NixOS module for this that doesn't pull in TLP (which
  # conflicts with power-profiles-daemon above), so poke sysfs directly.
  # Before a long trip, lift it for one charge without a rebuild:
  #   echo 100 | sudo tee /sys/class/power_supply/BAT0/charge_control_end_threshold
  systemd.services.battery-charge-threshold = {
    description = "Cap battery charge at 80% to limit calendar ageing";
    # Also runs on resume: After+WantedBy on suspend.target is the documented
    # post-resume idiom, and some ThinkPad ECs drop the threshold across sleep.
    # No RemainAfterExit — the unit must be able to go inactive to re-fire.
    wantedBy = [ "multi-user.target" "suspend.target" ];
    after = [ "suspend.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      bat=/sys/class/power_supply/BAT0
      # Order matters: the EC rejects a start value above the current end.
      if [ -w "$bat/charge_control_start_threshold" ]; then
        echo 75 > "$bat/charge_control_start_threshold"
      fi
      if [ -w "$bat/charge_control_end_threshold" ]; then
        echo 80 > "$bat/charge_control_end_threshold"
      fi
    '';
  };

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
