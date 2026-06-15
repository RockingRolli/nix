# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single Nix flake that produces two kinds of outputs from one shared base:

- `nixosConfigurations.<name>` — per-project NixOS dev VMs (headless or GUI).
- `homeConfigurations.rvo` — a standalone home-manager config so the same
  fish/dev-tool/Claude-Code setup runs on non-NixOS hosts (e.g. Fedora).

The design intent: project repos stay free of `.nix` files. `nix-ld` is enabled
system-wide so `uv`, `pnpm`, and `rustup` toolchains run unmodified;
reproducibility for projects comes from their own lockfiles. Project services
(postgres, redis) run via podman inside the project repo, never as NixOS modules
— the host config only enables podman.

## Commands

Validate before considering any change done:

```
nix flake check
nix build .#nixosConfigurations.<host>.config.system.build.toplevel --dry-run
```

Apply changes (the global justfile in `home/justfile` + `home/tasks/system.just`
is deployed to `~/.config/just/`, so these run from any directory as `just system::<recipe>`):

```
just system::pull           # nixos-rebuild switch from github, host = `hostname`
just system::test           # nixos-rebuild test (in-memory, reverts on reboot)
just system::rollback       # revert to previous generation
just system::diff           # nix store diff-closures vs current system
just system::gc             # garbage-collect + optimise store
```

Local iteration in a cloned repo (instead of the github flake the justfile uses):

```
sudo nixos-rebuild switch --flake .#<host>
```

Standalone home-manager (Fedora etc.):

```
nix run home-manager/release-26.05 -- switch --flake github:RockingRolli/nix#rvo
```

**Git gotcha (load-bearing):** flakes only see git-tracked files. After creating
or renaming any `.nix` file you MUST `git add <path>` before any rebuild/check,
or Nix evaluates as if the file doesn't exist.

## Architecture

A host is assembled by composing modules. There is no monolithic config — each
`hosts/<name>.nix` is a thin imports list plus host-specific bits (hostname,
bootloader, which home-manager profiles to layer).

**Host builder in `flake.nix`:** `mkHost ./hosts/<name>.nix` — each host file is
a thin imports list (hardware + base + whichever modules that host needs) plus
hostname and bootloader.

**Layering model:**

- `modules/base.nix` — the floor every host stands on: nix-ld, the `rvo` user,
  sshd, firewall, flakes, sudo NOPASSWD rules for the `system::` recipes. It is
  container-runtime-agnostic.
- `modules/virtualisation/{podman,docker}.nix` — the container runtime. Every
  host imports **exactly one** (they're mutually exclusive — both own the
  `docker` CLI and daemon socket, so importing both is a build-time conflict).
  `podman.nix` (with `dockerCompat`) is the default; `docker.nix` (Docker +
  docker-compose) is used by `tepavi-dev`. The `d`/`dc` fish functions in
  `home/common.nix` detect the runtime at shell startup, so the one shared home
  config works on both.
- `modules/desktop.nix` → `modules/desktop/niri.nix` + `desktop/vm.nix` — GUI
  layer (only `dev-desktop` uses it). Compositor config is system-side here;
  user-side theming is separate.
- `home/common.nix` — the user-config constant imported by every host AND by the
  standalone `homeConfigurations.rvo`. fish + dev tools + git + Claude Code.
- `home/gui.nix` — GUI-only home-manager additions, layered on top of
  `common.nix` only for GUI hosts.

**Two separate layers — don't confuse them:** system modules (`modules/`) vs.
user/home-manager config (`home/`). Headless hosts import only `common.nix`; GUI
hosts add `gui.nix`. `home/common.nix` is wired into NixOS hosts via
`home-manager.users.rvo.imports` in each host file (NOT centrally), so a GUI host
can layer `gui.nix` without affecting headless hosts.

**Adding/removing a feature** = editing a host's imports list. To add code-server
to `tepavi-dev`, add `../modules/services/code-server.nix` to its imports. To drop
a service, delete its import line.

## Conventions specific to this repo

- Bootloader config (`boot.loader.grub.*`) lives in `hosts/<name>.nix`, NOT in
  `hosts/hardware/<name>.nix`. The hardware file is overwritten by
  `nixos-generate-config` at install time; keeping bootloader settings in the host
  file means they survive hardware-config regeneration.
- `users.mutableUsers = true` — passwords are deliberately NOT declared in this
  repo. They live in `/etc/shadow` and don't follow a rebuild to fresh disk. SSH
  keys, groups, shell, home dir are still declarative.
- The fish `just` wrapper function (in `common.nix`) walks up the directory tree
  for a local justfile and falls back to the global one — so `just system::pull`
  works from anywhere.
- tide prompt is configured via a content-hash sentinel in `common.nix`
  `interactiveShellInit`: editing `tideArgs` invalidates the hash and triggers
  exactly one re-configure on next shell. Don't hand-run `tide configure`.

## dev-desktop one-time step

After first login on `dev-desktop`, run `dms setup niri` (interactive TUI) once to
populate `~/.config/niri/`. DMS owns that directory as user-mutable state; Home
Manager does not write it.

## Design docs

`docs/superpowers/{specs,plans}/` holds dated design/spec markdown for larger
changes (e.g. the niri+DMS VM work). Consult these for the reasoning behind the
desktop setup.
