# Minimal niri+DMS desktop VM — design

**Date:** 2026-06-12
**Status:** approved by user; ready for implementation plan

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
`modules/desktop.nix` + `modules/desktop/niri.nix` + `modules/laptop.nix`,
and inherits the same niri+DMS user-side config from `home/desktop/`.

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
- **Compositor + shell:** niri (via `github:sodiboo/niri-flake`) + DMS (via
  `github:AvengeMedia/DankMaterialShell/stable`).
- **Audio:** PipeWire enabled from day one — DMS uses it for per-app volume
  state in the panel.
- **Module modularity:** subdirectory split (`modules/desktop/`,
  `home/desktop/`) rather than flat. User has previously expressed preference
  for "more modular, not less" when the split is likely to be needed anyway.

## Verified package availability

- `niri` in `nixpkgs/nixos-26.05`: version 26.04. Module also re-exposed by
  `niri-flake` with richer config surface.
- `quickshell` in `nixpkgs/nixos-26.05`: 0.3.0 — meets DMS's stated minimum.
- `dms` flake at `github:AvengeMedia/DankMaterialShell` exposes
  `nixosModules.dank-material-shell`, `homeModules.dank-material-shell`, and
  `homeModules.niri`. `/stable` branch is the recommended pin.
- `spice-vdagent`, `qemu-guest-agent`, `greetd`, `pipewire`, `foot` — all
  in nixpkgs.

## Architecture

### Flake inputs (two new)

```nix
niri-flake = {
  url = "github:sodiboo/niri-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
dms = {
  url = "github:AvengeMedia/DankMaterialShell/stable";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Both passed through `extraSpecialArgs` to home-manager so home modules can
consume them — same pattern already used for `claude-code-nix`.

### Module tree (new files marked NEW; FILL-IN = stub gets populated)

```
modules/
  base.nix
  desktop.nix             FILL-IN: GUI base — PipeWire, polkit, NetworkManager, system fonts
  desktop/
    niri.nix              NEW: programs.niri.enable, xdg-desktop-portal, greetd autologin
    vm.nix                NEW: spice-vdagentd, qemu-guest service
  laptop.nix              existing stub
  workstation.nix         existing stub
  services/
    code-server.nix
home/
  common.nix
  gui.nix                 FILL-IN: foot terminal, fonts theming, GTK/Qt theming
  desktop/
    niri.nix              NEW: niri HM config via niri-flake's HM module (keybindings, outputs)
    dms.nix               NEW: imports dms.homeModules.dank-material-shell + dms.homeModules.niri
```

### Host file

- `hosts/dev-desktop.nix` (NEW): thin imports list —
  `./hardware/dev-desktop.nix` + `../modules/base.nix` +
  `../modules/desktop.nix` + `../modules/desktop/niri.nix` +
  `../modules/desktop/vm.nix`, plus `networking.hostName = "dev-desktop"` and
  `system.stateVersion = "26.05"`.
- `hosts/hardware/dev-desktop.nix` (NEW, placeholder): regenerated at install
  time from the actual VM via `nixos-generate-config`.

### Host-to-home-manager wiring

The current flake.nix sets `home-manager.users.rvo = import ./home/common.nix;`
inside the shared `hmModule`. This bakes in "everyone gets exactly common.nix"
which makes adding `gui.nix` for GUI hosts awkward.

**Decision:** move ownership of the user's home-manager module list from
`hmModule` to each host file. `hmModule` retains the wiring concerns
(`useGlobalPkgs`, `useUserPackages`, `extraSpecialArgs`); each host explicitly
declares which home modules its user gets:

- **Headless hosts** (`hosts/proj-api.nix`, `hosts/tepavi-dev.nix`, and any
  `mkUniformHost` member): `home-manager.users.rvo.imports = [ ../home/common.nix ];`
- **GUI hosts** (`hosts/dev-desktop.nix`, future laptop, workstation):
  `home-manager.users.rvo.imports = [ ../home/common.nix ../home/gui.nix ];`

`home/gui.nix` itself imports `./desktop/niri.nix` and `./desktop/dms.nix`,
so GUI hosts get the full niri+DMS user config by listing one file rather
than three.

**Refactor side-effect:** the implementation must update `mkHost`/`mkUniformHost`
in flake.nix to stop setting `users.rvo`, and update the existing
`hosts/proj-api.nix` and `hosts/tepavi-dev.nix` to declare it themselves.
Small change; preserves current behavior for those hosts.

## Component details

### `modules/desktop.nix` (GUI base — shared by every GUI host)

- `services.pipewire` enabled with `pulse`, `alsa`, `wireplumber`.
- `security.polkit.enable = true;` (already implied by lots of GUI stack,
  but explicit).
- `networking.networkmanager.enable = true;` (replaces direct
  `networking.useDHCP` for GUI hosts since users expect to manage Wi-Fi
  imperatively on real machines; harmless in the VM).
- `fonts.packages` with `inter` and `material-symbols` (DMS expects both),
  plus `nerd-fonts.jetbrains-mono` to render tide's prompt glyphs in foot
  and any other future terminal.
- `programs.dconf.enable = true;` (GTK theming bridge).
- `xdg.portal.enable = true;` + `xdg.portal.extraPortals` with
  `xdg-desktop-portal-gtk` — provides file pickers, screenshare to apps that
  ask the portal.

### `modules/desktop/niri.nix` (niri-specific system bits)

- Imports `niri-flake.nixosModules.niri`.
- `programs.niri.enable = true;`.
- `services.greetd` with `default_session.command = "${pkgs.niri}/bin/niri-session"`
  and `default_session.user = "rvo"` — this is the autologin.
- `xdg.portal.config.niri.default = [ "gtk" ];` — wire niri to the GTK portal.

### `modules/desktop/vm.nix` (guest agents for hypervisor conveniences)

Pixels and input already work without this module — virt-manager / Proxmox
negotiate SPICE with QEMU on the host side, and the guest renders to the
default virtio-gpu surface. This module adds the *conveniences* on top:

- `services.spice-vdagentd.enable = true;` — clipboard sharing host↔guest
  and dynamic resolution match when virt-viewer/remote-viewer window
  resizes.
- `services.qemuGuest.enable = true;` — qemu-ga socket; lets the hypervisor
  do graceful shutdowns via libvirt's API and time-sync after host suspend.
  ACPI shutdown still works without this; qemu-ga is the cooperative path.
- `virtio-gpu` kernel module is pulled in by the `qemu-guest.nix` profile
  already imported by hardware-configuration; no extra config.

### `home/gui.nix` (GUI HM base)

- `programs.foot.enable = true;` with a minimal config (font, padding,
  colors that don't fight DMS's Material theme).
- `gtk.enable = true;` with theme/cursor packages.
- `qt.enable = true;` with `qt.platformTheme = "gtk";` so Qt apps follow
  GTK theming.
- `fonts.fontconfig.enable = true;` (HM-side fontconfig).

### `home/desktop/niri.nix` (niri user config)

- Imports `niri-flake`'s home-manager module.
- `programs.niri.config` populated with starter content:
  - One output config (size + scale) — assume 1920x1200 for the VM, override
    later via the SPICE viewer's resize.
  - Bare-minimum keybindings: Super+Return = foot, Super+D = DMS launcher
    (via DMS's spawn command), Super+Q = close, Super+Shift+E = quit niri.
  - Empty `input.touchpad` block ready for later (laptop host will populate).
- Explicit goal: leave room for the user to iterate — this file is "the
  thing you'll edit a lot during testbed work."

### `home/desktop/dms.nix` (DMS user config)

- `imports = [ dms.homeModules.dank-material-shell dms.homeModules.niri ];`
- `programs.dank-material-shell.enable = true;`
- All feature flags left at defaults initially (they default `true` and pull
  their deps automatically: dgop, matugen, cava, khal, wtype).
- A future tuning pass can disable features the VM doesn't need (e.g.,
  `enableVPN = false;`).

## Bootstrap path (how the VM gets created)

1. Push the design (this spec) + the implementation (next phase).
2. Spin up a new VM in Proxmox or libvirt with virtio-gpu, virtio-vga,
   QXL/ICH9 audio if you want sound, and the NixOS minimal ISO mounted.
3. Boot ISO, partition + format with label `nixos`, mount `/mnt`.
4. `nixos-generate-config --root /mnt --dir /tmp/cfg`; copy
   `/tmp/cfg/hardware-configuration.nix` to
   `hosts/hardware/dev-desktop.nix` in the repo (push, or commit to the
   already-pushed branch).
5. `nixos-install --flake github:RockingRolli/nix#dev-desktop` (or
   `--flake /path/to/clone#dev-desktop` from a local clone).
6. Reboot, open SPICE viewer against the VM, greetd-autologin lands you in
   niri running DMS.

Once the VM exists, day-to-day workflow uses the existing `just system::pull`
recipe (recipe takes an optional `host` arg so the first apply after the
hostname is in place works fine).

## Verification

- **Eval-time:** `nix flake check` passes with no warnings; the
  `dev-desktop` nixosConfiguration evaluates to a buildable derivation.
- **Build-time:** `nix build .#nixosConfigurations.dev-desktop.config.system.build.toplevel`
  produces a .drv (the existing pattern for the other hosts).
- **Boot-time:** the VM reaches greetd, autologs in, niri starts, DMS panel
  appears.
- **Runtime smoke test:** open foot via Super+Return, type `echo hello`;
  open DMS launcher via Super+D and see Quickshell render correctly; resize
  the SPICE viewer window and confirm niri output adjusts.
- **Clipboard parity:** copy text in guest, paste on host (via SPICE
  vdagent).

## Scope

### In scope
- Two new flake inputs (niri-flake, DMS /stable).
- Two new system modules (`desktop/niri.nix`, `desktop/vm.nix`) plus
  populating `desktop.nix`.
- Two new home modules (`desktop/niri.nix`, `desktop/dms.nix`) plus
  populating `gui.nix`.
- One new host file pair (`hosts/dev-desktop.nix` + `hosts/hardware/dev-desktop.nix`).
- Plumbing the new flake inputs through `extraSpecialArgs` for both
  nixosSystem and the standalone `homeConfigurations.rvo`.
- README updates reflecting the new host + module shape.

### Out of scope (deferred to later passes)
- A real login screen instead of autologin (one greetd config change).
- Browser, IDE, office tools — added to `home/gui.nix` when they're
  actually needed for day-to-day work.
- PAM / swaylock / `loginctl lock-session` — irrelevant under autologin.
- Per-feature tuning of DMS flags (start with everything enabled, prune
  what the panel doesn't use).
- mDNS / `dev-desktop.local` reachability — connect by IP for now.
- Migrating the laptop and workstation to NixOS — that's the *consumer*
  of this design's reusable modules, not part of this iteration.
- Replacing `mutableUsers = false` with a password mechanism — independent
  decision, tracked separately.

## Risks / open follow-ups

- **`niri-flake`'s NixOS module vs nixpkgs's `programs.niri.enable`** — both
  exist. The flake's tracks more recent niri config schema. Default to the
  flake; if it churns too fast for comfort, switching to nixpkgs is a
  one-line `imports` change.
- **`dms.homeModules.niri` content is unknown to me at design time** — the
  doc says it provides "niri compositor integration" but I haven't read its
  source. Worst case: import does nothing useful and I drop it during
  implementation. Doesn't change the design's shape.
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
The user has not stated a preference for spec location; this is the default
from the brainstorming workflow. Move freely if it doesn't fit the repo's
documentation conventions long-term.
