flake := "github:RockingRolli/nix"
repo := "/home/rvo/dev/nix"

# Rebuild and switch to the latest config from github (override host for renames)
pull host=`hostname`:
    sudo nixos-rebuild switch --flake {{flake}}#{{host}} --refresh

# Bump flake inputs (newer tool versions), push, then rebuild from github
upgrade host=`hostname`:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{repo}}
    git pull --ff-only
    nix flake update
    if git diff --quiet flake.lock; then
        echo "flake.lock already up to date; nothing to upgrade."
    else
        git commit -m "flake: update inputs" flake.lock
        git push
    fi
    just system::pull {{host}}

# Apply config in memory only (rescue with reboot if broken)
test host=`hostname`:
    sudo nixos-rebuild test --flake {{flake}}#{{host}} --refresh

# Roll back to the previous generation
rollback:
    sudo nixos-rebuild switch --rollback

# Delete generations older than 7 days and optimize the store
gc:
    sudo nix-collect-garbage --delete-older-than 7d
    sudo nix-store --optimise

# Show what would change vs. what is currently installed
diff host=`hostname`:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(mktemp -d)/result
    nix build --refresh --out-link "$out" {{flake}}#nixosConfigurations.{{host}}.config.system.build.toplevel
    nix store diff-closures /run/current-system "$out"
    rm -rf "$(dirname "$out")"
