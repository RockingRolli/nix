{ config, pkgs, lib, ... }:

# GUI base for every host with a display. Headless hosts (proj-api,
# tepavi-dev) do not import this; GUI hosts (dev-desktop, future laptop) do,
# either directly or via ./laptop.nix.
{
  # Audio. DMS reads PipeWire state for per-app volume in the panel.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    wireplumber.enable = true;
  };

  # GUI hosts manage networks via NetworkManager (laptop wifi, nm-applet via
  # DMS). In a VM this still gets DHCP from the hypervisor.
  networking.networkmanager.enable = true;

  # GTK theming bridge — apps that store settings via dconf need this.
  programs.dconf.enable = true;

  # File manager. Thunar (GTK) fits the GTK theming already configured in
  # home/gui.nix (adw-gtk3 + xdg-desktop-portal-gtk) and is far lighter than
  # nemo/dolphin (~15 extra store paths vs ~100), which drag in MATE/Cinnamon
  # or the full KDE Frameworks stack respectively. The module (not a plain
  # package) wires up the plugin lookup dirs so volman/archive plugins load.
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman # automount + manage removable media (USB sticks etc.)
      thunar-archive-plugin # right-click create/extract archives
    ];
  };

  # gvfs backs Thunar's Trash, network-share browsing (smb/sftp) and
  # removable-media mounting; tumbler generates the thumbnails Thunar shows.
  # Neither is pulled in by the base niri/DMS closure, so enable both here.
  services.gvfs.enable = true;
  services.tumbler.enable = true;

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
