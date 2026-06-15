# nix

Per-project NixOS dev VMs + portable home-manager (fish) config, shared from one
flake.

- One `nixosConfigurations.<vm>` per project VM. Mix-and-match by which modules
  the host file imports.
- `home/common.nix` is the constant: identical fish/git/dev-tool/Claude-Code
  setup across every machine, plus a standalone `homeConfigurations.rvo` so
  the same config works on non-NixOS hosts (e.g. Fedora).
- `nix-ld` is enabled at the system level so `uv`, `pnpm`, and `rustup` work
  without per-project `.nix` files. Project repos stay clean — reproducibility
  there comes from `uv.lock` / `pnpm-lock.yaml` / `Cargo.lock`.
- Project-level services (postgres, redis, etc.) run via podman inside the
  project repo, not as NixOS service modules. The host config only enables
  podman; what runs on top is the project's concern.

## Layout

```
flake.nix                  # inputs + mkHost + outputs
modules/
  base.nix                 # nix-ld, user, ssh, podman, firewall, flakes, sudo rules
  desktop.nix              # GUI base: pipewire, polkit, networkmanager, fonts, dconf, xdg-portal
  desktop/
    niri.nix               # programs.niri.enable + programs.dms-shell.enable + tuigreet login
    vm.nix                 # spice-vdagentd + qemuGuest (guest-side conveniences)
  laptop.nix               # imports desktop + mobility extras (stub)
  services/
    code-server.nix        # OPTIONAL: services.code-server on 127.0.0.1
home/
  common.nix               # shared user config: fish + dev tools + Claude Code
  gui.nix                  # GUI HM additions on top of common: foot + GTK/Qt theming
  justfile + tasks/*.just  # global justfile deployed to ~/.config/just/
hosts/
  proj-api.nix             # base + code-server (one-off, headless)
  tepavi-dev.nix           # base only (one-off, headless)
  dev-desktop.nix          # base + desktop + desktop/niri + desktop/vm (GUI VM)
  hardware/
    proj-api.nix
    tepavi-dev.nix
    dev-desktop.nix        # placeholder until install regenerates
```

## Defining a host

Each `hosts/<name>.nix` is a thin imports list (hardware + base + whichever
modules that host needs) plus its hostname and bootloader. `mkHost` in
`flake.nix` wires it up with home-manager.

## Day-to-day workflow

```
nixos-rebuild switch --flake github:RockingRolli/nix#proj-api
nixos-rebuild switch --flake github:RockingRolli/nix#tepavi-dev
```

Local iteration (cloned repo):

```
sudo nixos-rebuild switch --flake .#proj-api
```

The `dev-desktop` host adds a SPICE-accessed niri+DMS desktop on top of the
same base. Connect via virt-manager's built-in viewer (libvirt) or Proxmox's
SPICE button — tuigreet prompts on tty1, then niri-session launches with DMS.

**One-time post-install step on dev-desktop**: log in once, then run
`dms setup niri` (interactive TUI) to populate `~/.config/niri/` with the
DMS-aware niri config fragments. DMS owns this directory as user-mutable
state — Home Manager does not write it.

**Git gotcha:** flakes only see files that are tracked by git. After creating
or renaming any file, run `git add <path>` before rebuilding or Nix will act
as if the file does not exist.

## Adding/removing a feature

A host file is just an imports list. Add code-server to `tepavi-dev`:

```nix
imports = [
  ./hardware/tepavi-dev.nix
  ../modules/base.nix
  ../modules/services/code-server.nix
];
```

Drop postgres from `proj-api`: delete the `../modules/postgres.nix` line.

## Reaching code-server

It binds to `127.0.0.1:4444` and is not exposed by the firewall. Forward over
SSH from your laptop:

```
ssh -L 4444:localhost:4444 rvo@<vm-host>
```

Then open <http://localhost:4444>.

## First-install bootstrap

`nixos-rebuild --flake` assumes the target is already NixOS. The first time you
provision a VM you need to get NixOS onto it.

### Proxmox VE

1. Upload the NixOS minimal ISO to the Proxmox local ISO storage.
2. Create a VM: BIOS = SeaBIOS (so the placeholder GRUB layout works as-is),
   disk = SCSI on `virtio-scsi`, at least 8 GiB RAM and 4 vCPU for builds.
3. Boot the ISO, partition + format with label `nixos`:
   ```
   parted /dev/sda -- mklabel msdos
   parted /dev/sda -- mkpart primary 1MiB 100%
   mkfs.ext4 -L nixos /dev/sda1
   mount /dev/disk/by-label/nixos /mnt
   ```
4. Get the flake onto /mnt and generate hardware-config:
   ```
   nix-shell -p git
   git clone https://github.com/RockingRolli/nix /mnt/etc/nixos-flake
   nixos-generate-config --root /mnt --dir /tmp/cfg
   cp /tmp/cfg/hardware-configuration.nix \
      /mnt/etc/nixos-flake/hosts/hardware/proj-api.nix
   ```
   Note: `boot.loader.grub.*` settings live in `hosts/<name>.nix`, not in
   `hosts/hardware/<name>.nix`. The hardware file gets overwritten by this
   copy step at install; bootloader config stays in the host file across
   regenerations.
5. Install:
   ```
   nixos-install --flake /mnt/etc/nixos-flake#proj-api
   reboot
   ```
6. Commit the regenerated `hosts/hardware/proj-api.nix` from your laptop and
   push so future rebuilds see it.

Alternatively, `nixos-anywhere` from your laptop is faster:

```
nix run github:nix-community/nixos-anywhere -- \
  --generate-hardware-config nixos-generate-config hosts/hardware/proj-api.nix \
  --flake .#proj-api root@<vm-ip>
```

(Boot the Proxmox VM into any Linux rescue/live env first so nixos-anywhere can
SSH in as root and take over.)

### libvirt/KVM

```
virt-install --name proj-api --memory 8192 --vcpus 4 \
  --disk size=40,bus=virtio --network bridge=virbr0 \
  --cdrom /var/lib/libvirt/images/nixos-minimal.iso --osinfo nixos-unknown
```

Then partition/install as in the Proxmox steps. nixos-anywhere works the same
way once the VM has a reachable SSH.

## Fedora (standalone home-manager)

The same fish/dev-tool setup, applied to your Fedora machines:

```
nix run home-manager/release-26.05 -- switch --flake github:RockingRolli/nix#rvo
```

To make fish the login shell on Fedora:

```
which fish | sudo tee -a /etc/shells
chsh -s "$(which fish)"
```

(NixOS handles this automatically via `users.users.rvo.shell` in
`modules/base.nix`; on Fedora `chsh` is the standard way.)

## Validation

```
nix flake check
nix build .#nixosConfigurations.proj-api.config.system.build.toplevel --dry-run
```
