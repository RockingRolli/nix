# Minimal niri+DMS desktop VM — design

**Date:** 2026-06-12
**Status:** shipped 2026-06-12 with an architecture pivot from the original design; current architecture documented below. Original design (niri-flake + DMS HM modules) was abandoned mid-implementation — see "Architecture pivot" section.

## Goal

Add a new NixOS host to the flake — `dev-desktop` — that boots into a niri
compositor session with DankMaterialShell (DMS) running on top, accessible via
SPICE from the hypervisor. The VM acts as a testbed for the user's intended
desktop config (niri+DMS) before that config lands on the physical laptop and
workstation, and is structured so it can grow into a daily-driver secondary
desktop without architectural changes.

The structural goal is equally important: the new modules establish the
"desktop / compositor / VM-display" axes so a future `hosts/laptop.nix` and
`hosts/workstation.nix` can reuse them with no copy-paste — the laptop imports
`modules/desktop.nix` + `modules/desktop/niri.nix` and inherits the same
system-level niri+DMS config.

## Confirmed constraints (from brainstorming)

- **Usage shape:** testbed-first, evolving into a secondary daily desktop.
  Design for fast iteration now; don't paint into corners.
- **Display path:** SPICE — the default that both Proxmox VE and
  libvirt/virt-manager already negotiate at the QEMU level, so pixels +
  input arrive without any guest-side config. The guest-side
  `spice-vdagentd` and `qemu-guest-agent` services are added for the
  ancillary conveniences (clipboard sharing, dynamic resolution,
  cooperative shutdown), not to make display work.
- **Login flow:** autologin straight into niri via greetd. No password prompt.
- **Audio:** PipeWire enabled from day one — DMS uses it for per-app volume
  state in the panel.
- **Module modularity:** subdirectory split (`modules/desktop/`) rather than
  flat. User has previously expressed preference for "more modular, not less"
  when the split is likely to be needed anyway.

## Architecture pivot (post-mortem)

**What the original design called for:** two new flake inputs (`niri-flake`
from `github:sodiboo/niri-flake` and `dms` from
`github:AvengeMedia/DankMaterialShell/stable`), HM modules for both
(`niri-flake.homeModules.niri` for declarative niri config, and
`dms.homeModules.dank-material-shell` + `dms.homeModules.niri` for DMS),
and home module files under `home/desktop/{niri,dms}.nix` imported by
`home/gui.nix`. All niri keybindings were to be declared via niri-flake's
`programs.niri.settings` schema (fully declarative).

**Why it failed:** niri-flake's HM module makes `~/.config/niri/config.kdl`
a read-only symlink into `/nix/store`. DMS's `dms setup niri` onboarding flow
assumes `~/.config/niri/config.kdl` is mutable user state — it reads the
existing file, merges its output-section fragments into it, and rewrites it.
These two systems compete for ownership of the same file, and neither can win
cleanly. A `home-manager.backupFileExtension = "backup"` workaround was added
during the initial pass but only masked the conflict: every `home-manager
switch` would clobber any manual niri config changes.

**Why the nixpkgs path is the right one:** reading DMS's own docs
(https://danklinux.com/docs/dankmaterialshell/nixos and
https://danklinux.com/docs/dankmaterialshell/nixos-flake) reveals that the
docs-canonical path is `programs.dms-shell` from nixpkgs plus a post-install
`dms setup` TUI step. DMS is architecturally built around the assumption that
the user mutates their compositor config imperatively via the `dms` tool. The
HM-declarative path is not documented because it fights the tool's own
config-management model. The right lesson: when integrating a tool that has
its own runtime config-management semantics, let the tool own the files it
claims. The cost is a one-time per-machine setup step; the win is no
file-ownership fights and no `home-manager switch` clobbering user config.

**What shipped:** both flake inputs were dropped, `home/desktop/{niri,dms}.nix`
were deleted, and all niri+DMS config moved to the system level. Commits
`a45426a`..`2121e81` cover the pivot.

## Architecture (shipped)

### Flake inputs

No new flake inputs for niri or DMS. Both are available in nixpkgs-26.05:
`programs.niri.enable` (nixpkgs module) and `programs.dms-shell.enable`
(nixpkgs module). No external flakes needed.

### Module tree (shipped)

```
modules/
  base.nix
  desktop.nix              GUI base — PipeWire, polkit, NetworkManager, system fonts
  desktop/
    niri.nix               programs.niri.enable, programs.dms-shell.enable,
                           greetd autologin (initial_session), tuigreet default_session
    vm.nix                 spice-vdagentd, qemu-guest service
  laptop.nix               existing stub
  workstation.nix          existing stub
  services/
    code-server.nix
home/
  common.nix
  gui.nix                  foot terminal, GTK/Qt theming, fontconfig
                           (NO desktop/ imports — DMS owns niri config)
hosts/
  dev-desktop.nix
  hardware/
    dev-desktop.nix
```

Note: `home/desktop/` does not exist. `home/gui.nix` is purely terminal +
theming; it does not import any niri or DMS home modules.

### Host file

- `hosts/dev-desktop.nix`: imports `./hardware/dev-desktop.nix` +
  `../modules/base.nix` + `../modules/desktop.nix` +
  `../modules/desktop/niri.nix` + `../modules/desktop/vm.nix`, plus
  `networking.hostName = "dev-desktop"` and `system.stateVersion = "26.05"`.
- `hosts/hardware/dev-desktop.nix`: placeholder; regenerated at install time.

### Host-to-home-manager wiring

`hmModule` was refactored to remove `users.rvo` ownership. Each host file
declares its own `home-manager.users.rvo.imports`:

- **Headless hosts** (`hosts/proj-api.nix`, `hosts/tepavi-dev.nix`):
  `home-manager.users.rvo.imports = [ ../home/common.nix ];`
- **GUI hosts** (`hosts/dev-desktop.nix`):
  `home-manager.users.rvo.imports = [ ../home/common.nix ../home/gui.nix ];`

`home/gui.nix` carries foot, GTK/Qt theming, and fontconfig — it does NOT
import `home/desktop/` files (that directory doesn't exist in the shipped
architecture).

## Component details (shipped)

### `modules/desktop.nix` (GUI base — shared by every GUI host)

- `services.pipewire` enabled with `pulse`, `alsa`, `wireplumber`.
- `security.polkit.enable = true;`
- `networking.networkmanager.enable = true;`
- `fonts.packages` with `inter` and `material-symbols` (DMS expects both),
  plus `nerd-fonts.jetbrains-mono`.
- `programs.dconf.enable = true;`
- `xdg.portal.enable = true;` + `xdg.portal.extraPortals` with
  `xdg-desktop-portal-gtk`.

### `modules/desktop/niri.nix` (niri + DMS, shipped)

This single file carries all niri+DMS system config. No niri-flake import.

- `programs.niri.enable = true;` (nixpkgs module).
- `programs.dms-shell.enable = true;` + `systemd.user.targets.dms-shell.wantedBy = [ "graphical-session.target" ];` for DMS autostart.
- `services.greetd` configured with two sessions:
  - `initial_session` (autologin): `command = "niri-session"`, `user = "rvo"` — greetd autologs in on first start.
  - `default_session` (fallback): `command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd niri-session"` — what greetd shows after a session exits.
- `xdg.portal.config.niri.default = [ "gtk" ];`

**Important:** niri's user-side config (`~/.config/niri/config.kdl` and
`~/.config/niri/dms/*.kdl` fragments) is **mutable user state, owned by DMS**.
It is NOT managed by Nix/HM. It is deployed once per VM via the `dms setup niri`
TUI step documented in the bootstrap path below. This is a deliberate trade:
accept one manual per-VM setup step; avoid file-ownership fights forever.

### `modules/desktop/vm.nix` (guest agents for hypervisor conveniences)

Pixels and input already work without this module. This adds:

- `services.spice-vdagentd.enable = true;` — clipboard sharing host↔guest
  and dynamic resolution match when virt-viewer/remote-viewer window resizes.
- `services.qemuGuest.enable = true;` — qemu-ga socket for graceful
  hypervisor-initiated shutdowns and time-sync after host suspend.

### `home/gui.nix` (GUI HM base — shipped)

- `programs.foot.enable = true;` with a minimal config (font, padding).
- `gtk.enable = true;` with theme/cursor packages.
- `qt.enable = true;` with `qt.platformTheme = "gtk";`.
- `fonts.fontconfig.enable = true;`

No niri or DMS imports. No `home/desktop/` subdirectory.

## Bootstrap path (how the VM gets created)

1. Push the shipped config.
2. Spin up a new VM in Proxmox or libvirt with virtio-gpu, virtio-vga,
   QXL/ICH9 audio if you want sound, and the NixOS minimal ISO mounted.
3. Boot ISO, partition + format with label `nixos`, mount `/mnt`.
4. `nixos-generate-config --root /mnt --dir /tmp/cfg`; copy
   `/tmp/cfg/hardware-configuration.nix` to
   `hosts/hardware/dev-desktop.nix` in the repo (push or commit to the
   already-pushed branch).
5. `nixos-install --flake github:RockingRolli/nix#dev-desktop` (or
   `--flake /path/to/clone#dev-desktop` from a local clone).
6. Reboot, open SPICE viewer against the VM, greetd-autologin lands you in
   niri.
7. **DMS setup (one-time, per-VM):** open a terminal (foot via greetd's
   tuigreet or a pre-existing keybind), run `dms setup niri`. Follow the TUI
   prompts. This writes `~/.config/niri/config.kdl` and the DMS fragment
   files. After this step, DMS's panel and niri integration are active.
8. Subsequent `nixos-rebuild switch` / `just system::pull` flows do not touch
   `~/.config/niri/` — that stays as mutable user state owned by DMS and
   the user.

Once the VM exists, day-to-day workflow uses the existing `just system::pull`
recipe.

## Verification

- **Eval-time:** `nix flake check` passes with no warnings; the
  `dev-desktop` nixosConfiguration evaluates to a buildable derivation.
- **Build-time:** `nix build .#nixosConfigurations.dev-desktop.config.system.build.toplevel`
  produces a .drv (the existing pattern for the other hosts).
- **Boot-time:** the VM reaches greetd, autologs in, niri starts, DMS panel
  appears after `dms setup niri` has been run.
- **Runtime smoke test:** open foot via a niri keybind; type `echo hello`;
  resize the SPICE viewer window and confirm niri output adjusts.
- **Clipboard parity:** copy text in guest, paste on host (via SPICE vdagent).

## Scope

### In scope (shipped)

- `modules/desktop/niri.nix` and `modules/desktop/vm.nix` (new files).
- Populate `modules/desktop.nix` (GUI base).
- `home/gui.nix` populated with foot + theming (no desktop/ imports).
- New host file pair (`hosts/dev-desktop.nix` + `hosts/hardware/dev-desktop.nix`).
- `hmModule` refactor: move `users.rvo` ownership to each host file.
- `dms setup niri` one-time per-VM manual step (documented, not automated).

### Out of scope (deferred)

- A real login screen instead of autologin.
- Browser, IDE, office tools.
- PAM / swaylock / `loginctl lock-session`.
- mDNS / `dev-desktop.local` reachability.
- Migrating the laptop and workstation to NixOS.
- Declarative niri keybinding management — the user edits
  `~/.config/niri/config.kdl` directly (or via DMS tooling) for now.

## Risks / open follow-ups

- **`niri-flake` vs nixpkgs's `programs.niri.enable`** — no longer
  relevant; we use the nixpkgs module. If niri config schema in nixpkgs lags
  behind niri upstream, revisit then.
- **DMS HM-module path (realized risk):** the DMS flake's `homeModules`
  were attempted and abandoned because they fight `dms setup`'s ownership of
  `~/.config/niri/config.kdl`. Don't revisit this without reading
  https://danklinux.com/docs/dankmaterialshell/nixos-flake carefully first —
  the docs-canonical path is the nixpkgs module + `dms setup`, not the HM
  modules.
- **Per-VM `dms setup` ritual:** every new VM (or fresh reinstall) requires
  a manual `dms setup niri` step before the DMS panel is active. This is
  intentional but worth documenting prominently for new machines. There is no
  automated way to run this without either bundling a DMS config as a Nix
  derivation (re-introduces the ownership fight) or writing a custom
  activation script (fragile). Accept the ritual for now.
- **SPICE audio routing depends on the hypervisor side**, not the guest. The
  guest will have functioning PipeWire whether or not it reaches the
  hypervisor. Configuring Proxmox/libvirt audio passthrough is the user's
  hypervisor-side step; not codified here.
- **Tide prompt + nerd font on a fresh VM** — when the host boots into niri
  and the user opens foot, the tide-configure-and-exec-fish dance happens.
  Should "just work" given foot is a Wayland terminal that handles the
  `exec fish` re-exec cleanly, but worth testing in the smoke pass.

## Out of band: spec location

This spec lives at `docs/superpowers/specs/2026-06-12-niri-dms-vm-design.md`.
