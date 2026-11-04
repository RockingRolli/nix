{ pkgs, osConfig, ... }:

# Lutris, on top of the Steam/gamescope/gamemode setup in ../modules/gaming.nix.
# A host importing this must import that module too: osConfig.programs.steam is
# read below.
{
  programs.lutris = {
    enable = true;

    # Must be the system's Steam, or Lutris brings up a second conflicting one.
    steamPackage = osConfig.programs.steam.package;

    extraPackages = with pkgs; [
      umu-launcher
      winetricks
      gamescope
      gamemode
      mangohud
    ];

    # Runners go here rather than in extraPackages, where Lutris does not detect
    # them properly. Lutris can still download others itself.
    protonPackages = [ pkgs.proton-ge-bin ];
    winePackages = [ pkgs.wineWow64Packages.staging ];
  };
}
