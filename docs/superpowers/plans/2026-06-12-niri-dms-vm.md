# niri+DMS desktop VM — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new NixOS host `dev-desktop` to the flake that boots into autologin'd niri + DMS, plus the reusable modules and home-manager fragments that future GUI hosts (laptop, workstation) will share.

**Architecture:** Modular split — `modules/desktop.nix` carries GUI base concerns, `modules/desktop/niri.nix` carries the compositor + greetd, `modules/desktop/vm.nix` carries guest agents. Home-manager mirrors: `home/gui.nix` for GUI base, `home/desktop/{niri,dms}.nix` for the niri+DMS user-side config. The host's `home-manager.users.rvo.imports` ownership moves from the shared `hmModule` into each host file so GUI vs headless hosts pick different module sets without touching the helpers.

**Tech Stack:** NixOS 26.05, home-manager release-26.05, niri-flake (`github:sodiboo/niri-flake`), DMS flake (`github:AvengeMedia/DankMaterialShell/stable`), greetd (autologin), spice-vdagentd + qemu-guest-agent.

**Spec:** `docs/superpowers/specs/2026-06-12-niri-dms-vm-design.md`

**Verification model for this plan:** Nix is declarative, so "tests" mean `nix flake check` (eval-only, catches type errors and assertion failures) + `nix eval .#nixosConfigurations.<host>.config.<option>` for specific assertions. The final smoke test is bootstrap-and-boot the VM, which is the last task and not subagent-automatable.

**Working directory:** `/home/rvo/dev/nix`. Throughout this plan, **after every code change, you must `git add -A` before `nix flake check`** — Nix flakes only see git-tracked files. Forgetting this manifests as "file not found" errors against paths that visibly exist on disk.

**Commit cadence:** commit after every task. Commit messages use the same terse style as recent history (`git log --oneline`); look at recent commits for tone.

---

## File map

### New files (created by this plan)

| Path | Responsibility |
|---|---|
| `modules/desktop/niri.nix` | System-side niri: `programs.niri.enable`, xdg-portals, greetd autologin to niri session. |
| `modules/desktop/vm.nix` | Guest agents only: spice-vdagentd + qemu-guest. Pixels work without this. |
| `home/desktop/niri.nix` | User-side niri config: import niri-flake's HM module, set keybindings + output starter content. |
| `home/desktop/dms.nix` | DMS user-side: import `dms.homeModules.dank-material-shell` + `dms.homeModules.niri`, enable. |
| `hosts/dev-desktop.nix` | Host file: thin imports list, hostname, stateVersion, declares `users.rvo.imports` for HM. |
| `hosts/hardware/dev-desktop.nix` | Placeholder hardware config (replaced at install time). |

### Modified files

| Path | Why |
|---|---|
| `flake.nix` | Add `niri-flake` and `dms` inputs; pass via `extraSpecialArgs`; remove `users.rvo` setting from `hmModule`; register `dev-desktop` in `nixosConfigurations`. |
| `modules/desktop.nix` | Populate (currently empty stub): PipeWire, polkit, NetworkManager, fonts, dconf, xdg-portal. |
| `home/gui.nix` | Populate (currently empty stub): foot terminal, GTK/Qt theming, fontconfig; also `imports` `./desktop/niri.nix` and `./desktop/dms.nix`. |
| `hosts/proj-api.nix` | Add `home-manager.users.rvo.imports = [ ../home/common.nix ];` (was previously in `hmModule`). |
| `hosts/tepavi-dev.nix` | Same as `proj-api.nix`. |
| `README.md` | Reflect new layout: `dev-desktop` host, `modules/desktop/`, `home/desktop/`. |

### Touched but unchanged

`modules/laptop.nix` and `modules/workstation.nix` already import `./desktop.nix`. Once `modules/desktop.nix` is populated, those stubs implicitly get its content — no edit needed.

---

## Task 1: Refactor `hmModule` to stop owning `users.rvo`

**Files:**
- Modify: `flake.nix` (the `hmModule` let-binding)
- Modify: `hosts/proj-api.nix` (add `users.rvo.imports`)
- Modify: `hosts/tepavi-dev.nix` (add `users.rvo.imports`)

Goal: behavior-preserving refactor. After this task, `proj-api` and `tepavi-dev` still produce the same toplevel derivation as before, but ownership of "which home modules does rvo get" lives in each host file.

- [ ] **Step 1.1: Record the current `proj-api` toplevel derivation path**

Run:
```bash
nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.proj-api.config.system.build.toplevel.drvPath 2>/dev/null
```

Save the output (looks like `"/nix/store/...nixos-system-proj-api-26.05.....drv"`). The path's *content hash* should be identical after Task 1's refactor. Record both `proj-api` and `tepavi-dev` paths now for comparison after the change.

- [ ] **Step 1.2: Remove `users.rvo` from `hmModule` in `flake.nix`**

In `flake.nix`, find the `hmModule` let-binding (around line 26-31). It currently reads:

```nix
hmModule = {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit claude-code-nix; };
  home-manager.users.rvo = import ./home/common.nix;
};
```

Replace with:

```nix
hmModule = {
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit claude-code-nix; };
  # users.<name>.imports is owned by each host file so GUI hosts can layer
  # gui.nix on top of common.nix without affecting headless hosts.
};
```

- [ ] **Step 1.3: Add `users.rvo.imports` to `hosts/proj-api.nix`**

Open `hosts/proj-api.nix`. After the `imports` list and before `system.stateVersion`, add:

```nix
  home-manager.users.rvo.imports = [ ../home/common.nix ];
```

The full attribute set should now contain that line — preserve everything else as-is.

- [ ] **Step 1.4: Add `users.rvo.imports` to `hosts/tepavi-dev.nix`**

Open `hosts/tepavi-dev.nix`. Same addition as Step 1.3, before `system.stateVersion`:

```nix
  home-manager.users.rvo.imports = [ ../home/common.nix ];
```

- [ ] **Step 1.5: Verify the flake still evaluates**

Run:
```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected output: ends with `checking flake output 'homeConfigurations'...` and no error/warning lines.

- [ ] **Step 1.6: Verify behavior preservation by comparing derivation paths**

Run:
```bash
nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.proj-api.config.system.build.toplevel.drvPath
nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.tepavi-dev.config.system.build.toplevel.drvPath
```

Expected: the .drv paths match the ones recorded in Step 1.1 byte-for-byte. If they differ, the refactor changed behavior — investigate before proceeding.

- [ ] **Step 1.7: Commit**

```bash
git add -A
git commit -m "refactor: move users.rvo.imports ownership from hmModule to host files"
```

---

## Task 2: Add `niri-flake` input

**Files:**
- Modify: `flake.nix`

- [ ] **Step 2.1: Add the input**

In `flake.nix`, inside the `inputs = { ... }` block, after `claude-code-nix`, add:

```nix
    niri-flake = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2.2: Add to the outputs function signature**

Find the `outputs = { self, nixpkgs, home-manager, agenix, claude-code-nix, ... }:` line. Insert `niri-flake` after `claude-code-nix`:

```nix
  outputs = { self, nixpkgs, home-manager, agenix, claude-code-nix, niri-flake, ... }:
```

- [ ] **Step 2.3: Pass through `specialArgs` and `extraSpecialArgs`**

In the same file, find `mkHost`'s `specialArgs`:

```nix
        specialArgs = { inherit agenix claude-code-nix; };
```

Change to:

```nix
        specialArgs = { inherit agenix claude-code-nix niri-flake; };
```

Do the same in `mkUniformHost`'s `specialArgs`.

Then update `hmModule`'s `extraSpecialArgs`:

```nix
  home-manager.extraSpecialArgs = { inherit claude-code-nix; };
```

becomes:

```nix
  home-manager.extraSpecialArgs = { inherit claude-code-nix niri-flake; };
```

Then update `homeConfigurations.rvo`'s `extraSpecialArgs`:

```nix
        extraSpecialArgs = { inherit claude-code-nix; };
```

becomes:

```nix
        extraSpecialArgs = { inherit claude-code-nix niri-flake; };
```

- [ ] **Step 2.4: Verify the flake evaluates with the new input**

Run:
```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -15
```

Expected: flake check passes. A new line in the output mentions adding the niri-flake input to the lock file the first time this runs. No errors.

- [ ] **Step 2.5: Commit**

```bash
git add -A
git commit -m "flake: add niri-flake input"
```

---

## Task 3: Add `dms` (DankMaterialShell) input

**Files:**
- Modify: `flake.nix`

Mirror Task 2 for the DMS flake. The pattern is identical; only the names differ.

- [ ] **Step 3.1: Add the input**

In `flake.nix` inputs block, after the `niri-flake` block, add:

```nix
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

The `/stable` branch is the docs-recommended pin.

- [ ] **Step 3.2: Add to the outputs function signature**

```nix
  outputs = { self, nixpkgs, home-manager, agenix, claude-code-nix, niri-flake, dms, ... }:
```

- [ ] **Step 3.3: Pass through `specialArgs` and `extraSpecialArgs`**

In `mkHost.specialArgs`:
```nix
        specialArgs = { inherit agenix claude-code-nix niri-flake dms; };
```

Same in `mkUniformHost.specialArgs`.

In `hmModule.extraSpecialArgs`:
```nix
  home-manager.extraSpecialArgs = { inherit claude-code-nix niri-flake dms; };
```

In `homeConfigurations.rvo.extraSpecialArgs`:
```nix
        extraSpecialArgs = { inherit claude-code-nix niri-flake dms; };
```

- [ ] **Step 3.4: Verify**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -15
```

Expected: flake check passes; lock file updates to include `dms` input.

- [ ] **Step 3.5: Commit**

```bash
git add -A
git commit -m "flake: add DankMaterialShell (dms) input pinned to /stable"
```

---

## Task 4: Populate `modules/desktop.nix` (GUI base)

**Files:**
- Modify: `modules/desktop.nix` (currently a stub)

Replace the entire file body. The current file is a `{ }` stub with comments.

- [ ] **Step 4.1: Write the populated module**

Replace the contents of `modules/desktop.nix` with:

```nix
{ config, pkgs, lib, ... }:

# GUI base for every host with a display. Headless hosts (proj-api,
# tepavi-dev) do not import this; GUI hosts (dev-desktop, future laptop +
# workstation) do, either directly or via ./laptop.nix / ./workstation.nix.
{
  # Audio. DMS reads PipeWire state for per-app volume in the panel.
  services.pipewire = {
    enable = true;
    pulse.enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    wireplumber.enable = true;
  };

  # GUI hosts manage networks via NetworkManager (laptop wifi, workstation
  # nm-applet via DMS). In a VM this still gets DHCP from the hypervisor.
  networking.networkmanager.enable = true;

  # GTK theming bridge — apps that store settings via dconf need this.
  programs.dconf.enable = true;

  # xdg-desktop-portal lets apps invoke file pickers, screenshare, etc.
  # without bundling a full DE. niri sets its own portal preference in
  # modules/desktop/niri.nix.
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };

  # Fonts. material-symbols + inter for DMS; jetbrains-mono nerd font for
  # tide glyphs in foot/terminal.
  fonts.packages = with pkgs; [
    inter
    material-symbols
    nerd-fonts.jetbrains-mono
  ];
  fonts.fontconfig.enable = true;

  # polkit is needed by GUI auth prompts (pkexec, mount, etc.).
  security.polkit.enable = true;
}
```

- [ ] **Step 4.2: Verify the module evaluates standalone**

The module isn't imported by any host yet, so a successful `flake check` only confirms there's no syntax error. Run:

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes. The new module isn't reached during checking yet — that's fine.

- [ ] **Step 4.3: Commit**

```bash
git add -A
git commit -m "modules/desktop: populate GUI base (pipewire, fonts, portal, networkmanager)"
```

---

## Task 5: Create `modules/desktop/niri.nix`

**Files:**
- Create: `modules/desktop/niri.nix`

- [ ] **Step 5.1: Create the directory and file**

Run:
```bash
mkdir -p /home/rvo/dev/nix/modules/desktop
```

Create `modules/desktop/niri.nix` with:

```nix
{ config, pkgs, lib, niri-flake, ... }:

# Niri compositor at the system level. The user-side niri config (keybinds,
# outputs) lives in home/desktop/niri.nix.
{
  imports = [ niri-flake.nixosModules.niri ];

  programs.niri.enable = true;

  # Niri prefers the gtk portal. The base portal module is enabled in
  # ../desktop.nix; this adds the niri-specific preference.
  xdg.portal.config.niri.default = [ "gtk" ];

  # greetd autologins rvo straight into a niri-session. To require a
  # password later, swap default_session.command for
  # "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd niri-session".
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.niri}/bin/niri-session";
        user = "rvo";
      };
    };
  };
}
```

- [ ] **Step 5.2: Verify standalone evaluation**

The module isn't imported by any host yet. Just verify the file parses:

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 5.3: Commit**

```bash
git add -A
git commit -m "modules/desktop/niri: niri + greetd autologin to niri-session"
```

---

## Task 6: Create `modules/desktop/vm.nix`

**Files:**
- Create: `modules/desktop/vm.nix`

- [ ] **Step 6.1: Create the file**

Create `modules/desktop/vm.nix` (the directory was created in Task 5):

```nix
{ config, pkgs, lib, ... }:

# Guest-side conveniences. Pixels and input already work without this module
# — virt-manager / Proxmox negotiate SPICE with QEMU on the host side and
# the guest renders to a virtio-gpu surface. This adds clipboard sharing,
# dynamic resolution, and cooperative shutdown.
{
  # Clipboard host<->guest + dynamic resolution match when the viewer
  # window is resized.
  services.spice-vdagentd.enable = true;

  # qemu-guest-agent socket. Lets the hypervisor do graceful shutdowns via
  # libvirt's API and time-sync after host suspend. ACPI shutdown still
  # works without this; qemu-ga is the cooperative path.
  services.qemuGuest.enable = true;
}
```

- [ ] **Step 6.2: Verify standalone evaluation**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 6.3: Commit**

```bash
git add -A
git commit -m "modules/desktop/vm: spice-vdagentd + qemuGuest for guest conveniences"
```

---

## Task 7: Create `home/desktop/niri.nix` (user-side niri config)

**Files:**
- Create: `home/desktop/niri.nix`

The starter content uses KDL because that's niri's native config format. Keybindings are minimal — enough to validate the testbed; the whole point is the user iterates here.

- [ ] **Step 7.1: Create the directory and file**

Run:
```bash
mkdir -p /home/rvo/dev/nix/home/desktop
```

Create `home/desktop/niri.nix` with:

```nix
{ config, pkgs, lib, niri-flake, ... }:

# User-side niri config. The system-side enable lives in
# ../../modules/desktop/niri.nix.
{
  imports = [ niri-flake.homeModules.niri ];

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
```

The `Mod+D` keybinding spawns DMS's spotlight via its IPC. If `qs` isn't on the user's `$PATH`, the spawn silently fails; that's surface-area to verify in the smoke test. The user can later wire it to a launcher of their preference.

- [ ] **Step 7.2: Verify standalone evaluation**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 7.3: Commit**

```bash
git add -A
git commit -m "home/desktop/niri: starter niri HM config (keybinds + single output)"
```

---

## Task 8: Create `home/desktop/dms.nix` (DMS user config)

**Files:**
- Create: `home/desktop/dms.nix`

- [ ] **Step 8.1: Create the file**

Create `home/desktop/dms.nix` (directory exists from Task 7):

```nix
{ config, pkgs, lib, dms, ... }:

# DankMaterialShell at the home-manager layer. dms.homeModules.niri adds
# the niri-side integration glue (recommended in the DMS docs).
{
  imports = [
    dms.homeModules.dank-material-shell
    dms.homeModules.niri
  ];

  programs.dank-material-shell.enable = true;

  # Feature flags default to true and pull in their respective tools:
  #   enableSystemMonitoring -> dgop
  #   enableVPN              -> nm-applet equivalents
  #   enableDynamicTheming   -> matugen
  #   enableAudioWavelength  -> cava
  #   enableCalendarEvents   -> khal
  #   enableClipboardPaste   -> wtype
  # Disable individual ones here if the panel doesn't use them, to keep
  # the closure smaller. Defaults are fine for first boot.
}
```

- [ ] **Step 8.2: Verify standalone evaluation**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 8.3: Commit**

```bash
git add -A
git commit -m "home/desktop/dms: DMS home modules + niri integration"
```

---

## Task 9: Populate `home/gui.nix` (GUI HM base + imports)

**Files:**
- Modify: `home/gui.nix` (currently empty stub)

- [ ] **Step 9.1: Write the populated module**

Replace the contents of `home/gui.nix` with:

```nix
{ config, pkgs, lib, ... }:

# GUI-only home-manager content. Imported by GUI hosts (dev-desktop and
# future laptop/workstation) on top of ./common.nix. Headless hosts do not
# import this.
{
  imports = [
    ./desktop/niri.nix
    ./desktop/dms.nix
  ];

  # Wayland-native terminal. Minimal config; iterate as desired.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=11";
        pad = "8x8";
        dpi-aware = "yes";
      };
      cursor.style = "beam";
      colors.alpha = 0.95;
    };
  };

  # GTK theming. Apps following xdg-desktop-portal honour these.
  gtk = {
    enable = true;
    cursorTheme = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
    };
    theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3";
    };
  };

  # Qt apps follow the GTK theme so foot, niri prompts, etc., look
  # consistent.
  qt = {
    enable = true;
    platformTheme.name = "gtk";
    style.name = "adwaita-dark";
  };

  fonts.fontconfig.enable = true;
}
```

- [ ] **Step 9.2: Verify the standalone homeConfigurations still evaluate**

`home/gui.nix` is NOT yet imported by the standalone `homeConfigurations.rvo` (that's still common.nix only — appropriate, since headless = no GUI). It IS now reachable through `home/desktop/{niri,dms}.nix`, which need the `niri-flake` and `dms` specialArgs.

Run:
```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes. If you see "attribute `niri-flake` missing" or similar, Step 2/3 didn't fully thread the specialArgs through — go back and check.

- [ ] **Step 9.3: Commit**

```bash
git add -A
git commit -m "home/gui: foot + GTK/Qt theming, import desktop/{niri,dms}"
```

---

## Task 10: Create `hosts/hardware/dev-desktop.nix` placeholder

**Files:**
- Create: `hosts/hardware/dev-desktop.nix`

Same pattern as `hosts/hardware/proj-api.nix` — minimum to evaluate, intended to be replaced at install time.

- [ ] **Step 10.1: Create the placeholder**

Create `hosts/hardware/dev-desktop.nix` with:

```nix
{ config, lib, modulesPath, ... }:

# PLACEHOLDER hardware configuration.
#
# Regenerate on the target VM during first install:
#   sudo nixos-generate-config --root /mnt --dir /tmp/cfg
#   cp /tmp/cfg/hardware-configuration.nix hosts/hardware/dev-desktop.nix
#
# Or via nixos-anywhere from your laptop:
#   nix run github:nix-community/nixos-anywhere -- \
#     --generate-hardware-config nixos-generate-config hosts/hardware/dev-desktop.nix \
#     --flake .#dev-desktop root@<vm-ip>

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/vda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
```

`/dev/vda` matches what virtio sees (tepavi-dev's real hardware config uses the same target). If you spin the VM up on a hypervisor that exposes the disk as `/dev/sda` instead, the install-time regeneration will fix this.

- [ ] **Step 10.2: Verify standalone evaluation**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 10.3: Commit**

```bash
git add -A
git commit -m "hosts/hardware/dev-desktop: placeholder for install-time regen"
```

---

## Task 11: Create `hosts/dev-desktop.nix`

**Files:**
- Create: `hosts/dev-desktop.nix`

This is the file that pulls everything together. Imports list + the host's home-manager imports.

- [ ] **Step 11.1: Create the host file**

Create `hosts/dev-desktop.nix` with:

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware/dev-desktop.nix
    ../modules/base.nix
    ../modules/desktop.nix
    ../modules/desktop/niri.nix
    ../modules/desktop/vm.nix
  ];

  networking.hostName = "dev-desktop";

  # GUI host: layer gui.nix on top of common.nix. gui.nix imports
  # ../home/desktop/{niri,dms}.nix internally.
  home-manager.users.rvo.imports = [
    ../home/common.nix
    ../home/gui.nix
  ];

  system.stateVersion = "26.05";
}
```

- [ ] **Step 11.2: Verify standalone evaluation**

The file exists but isn't yet referenced from `flake.nix` — flake check won't reach it. That's the next task. For now confirm there's no syntax error:

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -10
```

Expected: passes.

- [ ] **Step 11.3: Commit**

```bash
git add -A
git commit -m "hosts/dev-desktop: base + desktop + niri + vm; gui.nix in home"
```

---

## Task 12: Register `dev-desktop` in `nixosConfigurations`

**Files:**
- Modify: `flake.nix`

This is the task where flake-check actually exercises the full new module tree. Expect potentially surprising errors here from genuinely broken module composition (mismatched option names, wrong types) — if anything cracks open, this is where.

- [ ] **Step 12.1: Add the entry**

In `flake.nix`, find the `nixosConfigurations =` block:

```nix
      nixosConfigurations =
        (nixpkgs.lib.genAttrs uniformHosts mkUniformHost) // {
          proj-api = mkHost ./hosts/proj-api.nix;
          tepavi-dev = mkHost ./hosts/tepavi-dev.nix;
        };
```

Add `dev-desktop` to the right-hand attrset:

```nix
      nixosConfigurations =
        (nixpkgs.lib.genAttrs uniformHosts mkUniformHost) // {
          proj-api = mkHost ./hosts/proj-api.nix;
          tepavi-dev = mkHost ./hosts/tepavi-dev.nix;
          dev-desktop = mkHost ./hosts/dev-desktop.nix;
        };
```

- [ ] **Step 12.2: Run flake check — this is the real test**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -30
```

Expected: ends with `checking flake output 'homeConfigurations'...` and no error lines. The `nixosConfigurations.dev-desktop` line should appear in the output.

If errors appear, common causes:
- `attribute 'niri-flake' missing` → specialArgs not threaded; go back to Task 2.
- `option 'programs.dank-material-shell.enable' does not exist` → DMS HM module didn't import correctly; check Task 8.
- `option 'programs.niri.settings' does not exist` → niri-flake HM module didn't import correctly; check Task 7.

- [ ] **Step 12.3: Verify the toplevel derivation evaluates**

```bash
nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.dev-desktop.config.system.build.toplevel.drvPath
```

Expected: a `.drv` path like `/nix/store/...-nixos-system-dev-desktop-26.05....drv`. If this evaluates, the entire module tree composes cleanly.

- [ ] **Step 12.4: Verify autologin wiring resolves to the right command**

```bash
nix --extra-experimental-features 'nix-command flakes' eval .#nixosConfigurations.dev-desktop.config.services.greetd.settings.default_session.command
```

Expected: a string ending in `/bin/niri-session`. If empty or missing, Task 5's greetd block didn't take effect — check ordering in the host imports.

- [ ] **Step 12.5: Commit**

```bash
git add -A
git commit -m "flake: register nixosConfigurations.dev-desktop"
```

---

## Task 13: Update `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 13.1: Update the Layout block**

Open `README.md` and find the layout section (around the `## Layout` header). Replace the `modules/` and `home/` block contents with:

```
modules/
  base.nix                 # nix-ld, user, ssh, podman, firewall, flakes, sudo rules
  desktop.nix              # GUI base: pipewire, polkit, networkmanager, fonts, dconf, xdg-portal
  desktop/
    niri.nix               # programs.niri.enable + greetd autologin to niri-session
    vm.nix                 # spice-vdagentd + qemuGuest (guest-side conveniences)
  laptop.nix               # imports desktop + mobility extras (stub)
  workstation.nix          # imports desktop + heavier-hardware extras (stub)
  services/
    code-server.nix        # OPTIONAL: services.code-server on 127.0.0.1
home/
  common.nix               # shared user config: fish + dev tools + Claude Code
  gui.nix                  # GUI HM base: foot + GTK/Qt theming; imports desktop/{niri,dms}
  desktop/
    niri.nix               # niri HM config (keybindings + outputs)
    dms.nix                # DMS home modules + niri integration
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

- [ ] **Step 13.2: Add a "GUI VMs" sentence to the "Two ways to define a host" or "Day-to-day workflow" section**

Append after the existing `tepavi-dev` example one short paragraph:

```
The `dev-desktop` host adds a SPICE-accessed niri+DMS desktop on top of the
same base. Connect via virt-manager's built-in viewer (libvirt) or
Proxmox's SPICE button — greetd auto-logs rvo into niri.
```

- [ ] **Step 13.3: Verify flake check still passes (README doesn't affect eval, sanity check only)**

```bash
git add -A
nix --extra-experimental-features 'nix-command flakes' flake check --no-build 2>&1 | tail -5
```

Expected: passes.

- [ ] **Step 13.4: Commit**

```bash
git add -A
git commit -m "README: document dev-desktop host + desktop/ module layout"
```

---

## Task 14 (manual, not subagent-automatable): Bootstrap the VM and smoke-test

This task cannot be done by a subagent — it requires a hypervisor, a running VM, and manual interaction. Treat it as the acceptance test for the whole plan.

- [ ] **Step 14.1: Push the changes**

```bash
git push
```

- [ ] **Step 14.2: Create the VM in your hypervisor**

In Proxmox or virt-manager:
- 4 vCPU, 8 GiB RAM minimum
- 40 GiB virtio disk
- virtio-gpu (or QXL) display
- ich9-intel-hda or similar for audio (optional but enables SPICE audio passthrough)
- NixOS minimal ISO mounted

- [ ] **Step 14.3: Install NixOS**

Boot the ISO, partition + format with label `nixos`:

```bash
parted /dev/vda -- mklabel msdos
parted /dev/vda -- mkpart primary 1MiB 100%
mkfs.ext4 -L nixos /dev/vda1
mount /dev/disk/by-label/nixos /mnt
```

Generate hardware config, copy into the flake clone, install:

```bash
nix-shell -p git
git clone https://github.com/RockingRolli/nix /mnt/etc/nixos-flake
nixos-generate-config --root /mnt --dir /tmp/cfg
cp /tmp/cfg/hardware-configuration.nix /mnt/etc/nixos-flake/hosts/hardware/dev-desktop.nix
nixos-install --flake /mnt/etc/nixos-flake#dev-desktop
reboot
```

- [ ] **Step 14.4: Commit the regenerated hardware config**

From your laptop, after the install succeeds:

```bash
# Copy the actual hardware-configuration.nix back from the VM:
scp rvo@<vm-ip>:/etc/nixos-flake/hosts/hardware/dev-desktop.nix \
    hosts/hardware/dev-desktop.nix

git add hosts/hardware/dev-desktop.nix
git commit -m "hosts/hardware/dev-desktop: real config from VM install"
git push
```

- [ ] **Step 14.5: Smoke test the desktop**

Connect to the VM via virt-manager (libvirt) or the SPICE button (Proxmox). Verify:

- Greetd autologin lands directly in niri with no password prompt.
- DMS panel renders (top bar with status icons, clock, etc.).
- `Mod+Return` opens foot.
- In foot: prompt renders correctly (tide + JetBrainsMono Nerd Font glyphs).
- `Mod+Q` closes the foot window.
- Resize the virt-manager / SPICE viewer window: niri's output resolution follows (spice-vdagentd working).
- Select text in foot, paste it into an app on your host: clipboard sharing works.
- `Mod+Shift+E` quits niri (lands you back at the greetd autologin, which immediately re-launches niri — so the VM never sits at a login prompt).

If any of these fail, the corresponding module is the suspect. Note which failed and address before considering the task complete.

- [ ] **Step 14.6: Final commit if any tuning was needed**

If hostname, hardware-config, or a module needed adjustments during smoke testing, commit them:

```bash
git add -A
git commit -m "tweaks from dev-desktop bootstrap"
git push
```

---

## Coverage check against the spec

| Spec section | Plan task(s) |
|---|---|
| Flake inputs (niri-flake, dms) | Task 2, 3 |
| Module subdirectories under `modules/desktop/` | Task 5, 6 |
| `modules/desktop.nix` populated | Task 4 |
| Module subdirectories under `home/desktop/` | Task 7, 8 |
| `home/gui.nix` populated, imports desktop/* | Task 9 |
| Host-to-HM wiring refactor | Task 1 |
| Existing hosts (proj-api, tepavi-dev) updated | Task 1 (sub-steps 1.3, 1.4) |
| New host file `hosts/dev-desktop.nix` | Task 11, 12 |
| Hardware config placeholder | Task 10 |
| README updates | Task 13 |
| Bootstrap + smoke test | Task 14 |
| Verification model (flake check + eval) | Every task ends in flake check; Task 12 adds targeted evals |

No gaps.

## Notes on commit style

Recent history uses terse subjects ("tide config", "nopasswd"). The plan's commit messages are slightly longer ("modules/desktop/niri: ...") because they're scoped to a specific subsystem and more useful for future archaeology. If you prefer the existing terse style, shorten each subject to the leading identifier — the meaning carries either way.
