{ config, pkgs, lib, ... }:

# User-side niri config. The system-side enable lives in
# ../../modules/desktop/niri.nix.
#
# niri-flake.homeModules.config is already injected via
# niri-flake.nixosModules.niri → home-manager.sharedModules, so we must NOT
# import homeModules.niri here — doing so would declare programs.niri.finalConfig
# twice and cause an evaluation error.
{
  programs.niri.settings = {
    # Starter keybindings — iterate freely. niri-flake supports both the
    # nested attrset form (used here) and a raw KDL string via
    # programs.niri.config. Stick with settings for type-checked editing.
    binds = {
      "Mod+Return".action.spawn = "foot";
      "Mod+D".action.spawn = [ "qs" "-c" "DankMaterialShell" "ipc" "call" "spotlight" "toggle" ];
      "Mod+Q".action.close-window = { };
      "Mod+Shift+E".action.quit = { };
      "Mod+H".action.focus-column-left = { };
      "Mod+L".action.focus-column-right = { };
      "Mod+J".action.focus-window-down = { };
      "Mod+K".action.focus-window-up = { };
      "Mod+Shift+H".action.move-column-left = { };
      "Mod+Shift+L".action.move-column-right = { };
    };

    # Single output, sane default. SPICE viewer resizing + spice-vdagentd
    # will adjust the effective resolution at runtime via vdagent.
    outputs."Virtual-1" = {
      mode.width = 1920;
      mode.height = 1200;
      scale = 1.0;
    };

    # Touch input block left empty — laptop host will populate via mkMerge
    # when that comes.
    input.touchpad = { };
  };
}
