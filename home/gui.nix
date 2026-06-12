{ config, pkgs, lib, ... }:

# GUI-only home-manager bits. Import this in addition to ./common.nix on
# hosts with a display (laptop, workstation).
#
# Empty for now — populate when the first GUI host lands. Candidates:
#   - programs.alacritty / ghostty / wezterm (terminal emulator)
#   - programs.firefox (browser + sane defaults)
#   - fonts.fontconfig + the nerd font tide needs
#   - programs.vscode if you want it managed by nix
#   - GTK/Qt theming
{
}
