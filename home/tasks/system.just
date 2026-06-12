host := `hostname`
flake := "github:RockingRolli/nix"

# Rebuild and switch to the latest config from github
pull:
    sudo nixos-rebuild switch --flake {{flake}}#{{host}} --refresh

# Apply config in memory only (rescue with reboot if broken)
test:
    sudo nixos-rebuild test --flake {{flake}}#{{host}} --refresh

# Roll back to the previous generation
rollback:
    sudo nixos-rebuild switch --rollback

# Delete generations older than 7 days and optimize the store
gc:
    sudo nix-collect-garbage --delete-older-than 7d
    sudo nix-store --optimise

# Show what would change vs. what is currently installed
diff:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(mktemp -d)/result
    nix build --refresh --out-link "$out" {{flake}}#nixosConfigurations.{{host}}.config.system.build.toplevel
    nix store diff-closures /run/current-system "$out"
    rm -rf "$(dirname "$out")"
