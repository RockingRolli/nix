{ config, pkgs, lib, ... }:

# Laptop-class host: desktop base + mobility/power/firmware bits for a
# bare-metal ThinkPad (T14s Gen4 AMD, Phoenix / Radeon 780M). Because this is
# real hardware it imports desktop.nix but NOT desktop/vm.nix (that module is
# spice/qemu-guest guest conveniences only relevant inside a hypervisor).
{
  imports = [
    ./desktop.nix

    # PAM is sequential: pam_fprintd runs first and blocks until it gives up,
    # and only then does pam_unix get to ask for a password. Its defaults
    # (max-tries=3, timeout=30) expire at exactly DankGreeter's own 30s auth
    # watchdog, so the password prompt never arrives and login just errors out.
    # Bound it well inside that budget so every stack keeps a usable fallback.
    # Enabling fprintd puts pam_fprintd in front of ~30 services (sudo, login,
    # su, polkit-1, sshd, ...), so extend the submodule rather than list them.
    {
      options.security.pam.services = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { config, ... }:
            {
              # mkIf sits at `rules.auth`, not on the leaf: naming
              # rules.auth.fprintd at all would instantiate the rule for
              # services opting out of the default set (`other`), where it has
              # no modulePath or order.
              config.rules.auth = lib.mkIf config.useDefaultRules {
                fprintd.settings = {
                  max-tries = 2;
                  timeout = 10;
                };
              };
            }
          )
        );
      };
    }
  ];

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

  # Fingerprint reader (T14s Gen4 AMD ships a Goodix sensor). Enrol once with
  # `fprintd-enroll`; harmless if unsupported (fprintd just finds no device).
  # Enabling it defaults security.pam.services.*.fprintAuth to true, so login,
  # sudo and greetd all accept a fingerprint. This module is laptop-only, which
  # is what keeps pam_fprintd off sensorless hosts.
  services.fprintd.enable = true;

  # DankGreeter offers fingerprint when it finds pam_fprintd in
  # /etc/pam.d/greetd. Stated explicitly so it doesn't rest on the default.
  security.pam.services.greetd.fprintAuth = true;

  # ...but not over the network. base.nix disables password and
  # keyboard-interactive auth, so sshd never reaches its PAM auth stack today —
  # this only stops fingerprint becoming the sole accepted factor there if
  # KbdInteractiveAuthentication is ever turned on. A remote attempt would
  # otherwise arm the sensor here, and whoever touched it would complete a
  # login they can't see.
  security.pam.services.sshd.fprintAuth = false;

  # CLI helpers: backlight control (niri brightness keybinds shell out to
  # brightnessctl) and power debugging.
  environment.systemPackages = with pkgs; [
    brightnessctl
    powertop
  ];
}
