{ config, pkgs, lib, ... }:

# User-side niri config. The system-side compositor enable lives in
# ../../modules/desktop/niri.nix.
#
# On the nixpkgs path, niri config is user-mutable state: DMS owns
# ~/.config/niri/* and populates it via `dms setup niri` (interactive TUI
# run once after install). There is nothing to declare here at the
# home-manager layer — niri-flake's programs.niri.settings is not used.
{ }
