{ config, pkgs, lib, ... }:

# GUI base for every host with a display. Headless hosts (proj-api,
# tepavi-dev) do not import this; GUI hosts (dev-desktop, future laptop +
# workstation) do, either directly or via ./laptop.nix / ./workstation.nix.
{
  # Audio. DMS reads PipeWire state for per-app volume in the panel.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    wireplumber.enable = true;
  };

  # GUI hosts manage networks via NetworkManager (laptop wifi, workstation
  # nm-applet via DMS). In a VM this still gets DHCP from the hypervisor.
  networking.networkmanager.enable = true;

  # GTK theming bridge — apps that store settings via dconf need this.
  programs.dconf.enable = true;

  # xdg-desktop-portal lets apps invoke file pickers, screenshare, etc.
  # without bundling a full DE. niri sets its own portal preference in
  # modules/desktop/niri.nix.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Fonts. material-symbols + inter for DMS; jetbrains-mono nerd font for
  # tide glyphs in foot/terminal.
  fonts.packages = with pkgs; [
    inter
    material-symbols
    nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig.enable = true;

  # rtkit allows PipeWire to request realtime scheduling priority.
  # Without this, PipeWire runs at normal priority and adds avoidable latency.
  security.rtkit.enable = true;

  # polkit is needed by GUI auth prompts (pkexec, mount, etc.).
  security.polkit.enable = true;
}
