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

Apply changes. `nh` is enabled in `modules/base.nix` with `NH_FLAKE` set to the
github ref; the `sys-*` entries are fish abbreviations in `home/common.nix`
`shellAbbrs` that expand to the real `nh` command:

```
sys-pull       # → nh os switch --refresh   (build + activate + make boot default)
sys-test       # → nh os test --refresh     (in-memory, reverts on reboot)
sys-rollback   # → nh os rollback
sys-gc         # → nh clean all --keep-since 7d --optimise
sys-local      # → nh os switch ~/dev/nix        (dev machines only)
sys-update     # → nix flake update --flake ~/dev/nix   (dev machines only)
```

`sys-local` builds the working tree rather than github, for in-progress work.
The host is taken from `hostname`, so it needs no per-machine variant; pass
`-H <host>` to override. Flakes only see tracked files — `git add` before it.

`nh os switch` prints the closure diff itself, so there is no diff verb.
`nh os info` lists generations. Switching prompts for a sudo password — see the
comment above `security.sudo.extraRules` in `modules/base.nix`.

`sys-update` needs a clone. Github is the source of truth, so inputs get bumped
and pushed from a dev machine. Do not pass `--update` to `nh os switch` on a
pull-only host: against a github ref it evaluates fresh inputs but cannot
persist the lock, silently desyncing that machine.

Local iteration in a cloned repo (instead of the github flake nh uses):

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
  sshd, firewall, flakes, `programs.nh` (with `NH_FLAKE`), sudo rules. It is
  container-runtime-agnostic.
- `modules/virtualisation/{podman,docker}.nix` — the container runtime. Every
  host imports **exactly one** (they're mutually exclusive — both own the
  `docker` CLI and daemon socket, so importing both is a build-time conflict).
  `docker.nix` (Docker + compose v2) is used by `laptop`, `dev-desktop`,
  `tepavi-dev`, and `openclaw`; `podman.nix` (with `dockerCompat`) remains on
  `proj-api`. The
  `d`/`dc` fish functions in
  `home/common.nix` detect the runtime at shell startup, so the one shared home
  config works on both.
- `modules/desktop.nix` → `modules/desktop/niri.nix` + `desktop/vm.nix` — GUI
  layer (only `dev-desktop` uses it). Compositor config is system-side here;
  user-side theming is separate.
- `home/common.nix` — the user-config constant imported by every host AND by the
  standalone `homeConfigurations.rvo`. fish + dev tools + git + Claude Code.
- `home/gui.nix` — GUI-only home-manager additions, layered on top of
  `common.nix` only for GUI hosts.
- `modules/services/openclaw.nix` + `home/openclaw.nix` — the OpenClaw agent,
  split the same way: system prerequisites (overlay, linger, secrets dir,
  binary cache) vs. the user-scoped gateway config. Only `openclaw` imports
  them. See "openclaw host" below.

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
- System management is `sys-*` fish **abbreviations** (`common.nix`
  `shellAbbrs`), not functions — so the real `nh` command lands on the prompt,
  editable and covered by nh's own completions. Cost: abbreviations are
  interactive-only, so `ssh <host> sys-pull` does not work. If that is ever
  needed, use `programs.fish.functions` with `--wraps "nh os switch"`.
- tide prompt is configured via a content-hash sentinel in `common.nix`
  `interactiveShellInit`: editing `tideArgs` invalidates the hash and triggers
  exactly one re-configure on next shell. Don't hand-run `tide configure`.

## dev-desktop one-time step

After first login on `dev-desktop`, run `dms setup niri` (interactive TUI) once to
populate `~/.config/niri/`. DMS owns that directory as user-mutable state; Home
Manager does not write it.

## openclaw host

Runs an OpenClaw agent (Telegram in, tools out) as a systemd **user** service
under `rvo`. Packaging comes from the `nix-openclaw` flake input — openclaw is
not in nixpkgs, so the input is not optional. Two upstream modules exist; this
repo uses the home-manager one (`homeManagerModules.openclaw`), which is the
supported path and carries plugin/skill/workspace wiring. The NixOS module
(`nixosModules.openclaw-gateway`) is a bare systemd unit with none of that.

Consequences worth knowing before editing `home/openclaw.nix`:

- The gateway runs with `OPENCLAW_NIX_MODE=1`, so `openclaw plugins install`
  and friends deliberately fail. Plugins are `bundledPlugins` /
  `runtimePlugins` in the nix config plus a rebuild — never imperative.
- `~/.openclaw/openclaw.json` is generated and force-symlinked on activation.
  Hand edits are lost. `programs.openclaw.config` is schema-typed, so a wrong
  key is an eval error, not silently-ignored JSON.
- `users.users.rvo.linger` (in `modules/services/openclaw.nix`) is what keeps
  the bot alive without a login session and across reboots; the `[Install]`
  section that makes it start at all is added in `home/openclaw.nix`, because
  upstream's unit ships without one.

Secrets are runtime files under `/var/lib/openclaw-secrets` (dir created by
tmpfiles, contents written once by hand), matching the repo's
`mutableUsers = true` stance — nothing secret in git, nothing in the store.
Before the first `sys-pull` on a fresh box:

```
install -m600 /dev/stdin /var/lib/openclaw-secrets/telegram-bot-token <<< '<BotFather token>'
openssl rand -hex 32 | install -m600 /dev/stdin /var/lib/openclaw-secrets/gateway-token
```

Then replace the placeholder `allowFrom` Telegram user id in
`home/openclaw.nix` — an unedited list means the bot ignores every message.

### openclaw one-time steps

Two things are runtime state, not rebuild output, and both are per-machine:

1. **`claude` login as rvo.** Claude runs on the subscription, not an API key.
   Anthropic blocks subscription OAuth for third-party apps; the sanctioned
   path is reusing a Claude Code login on the same host, so the config keeps
   the canonical `anthropic/claude-opus-5` reference and sets
   `agents.defaults.models."anthropic/claude-opus-5".agentRuntime.id =
   "claude-cli"`. Run `claude` once as rvo and log in — until then every
   Anthropic turn fails. Never set `ANTHROPIC_API_KEY` on this host: it
   silently flips the CLI to pay-as-you-go API billing.
2. **Whisper weights.** The first voice message downloads `ggml-small.bin`
   (~500MB) into `~/.cache/whisper-cpp`, so that first reply is slow. Warm it
   with `openclaw-transcribe <some.ogg>`.

### Voice notes

Inbound audio is transcribed locally by a `writeShellApplication` wrapper
(`home/openclaw.nix`) around ffmpeg + whisper.cpp, wired in as an explicit
`tools.media.models` CLI entry. Explicit rather than relying on OpenClaw's
auto-detection, which would otherwise reach for a cloud provider first.
`echoTranscript` is on so a misheard note is visible. The ggml model is not in
nixpkgs, hence the runtime download above; change `whisperModel` in
`home/openclaw.nix` to trade accuracy for speed.

Models: Anthropic (via the CLI, see above) is primary, with a LAN ollama at
`http://10.0.0.234:11434` declared as a second provider. No model list is
pinned for it — run `openclaw models list` and reference tags as
`ollama/<tag>`.

### Network exposure

The gateway binds the LAN address (`gateway.bind = "lan"`), so the control UI
is reachable at `http://<host-ip>:18789` from the network.
`modules/services/openclaw.nix` opens 18789 to `10.0.0.0/24` only, via
`networking.firewall.extraCommands` (`allowedTCPPorts` cannot express a source
restriction). Two consequences worth remembering:

- OpenClaw refuses a non-loopback bind without token or password auth, so
  `gateway.auth` is load-bearing, not decoration.
- Plain http off loopback needs `gateway.controlUi.allowInsecureAuth = true`,
  which means the token crosses the LAN in clear. Moving to
  `bind = "tailnet"` or a TLS reverse proxy is what removes that flag.

Service: `systemctl --user status openclaw-gateway`, logs at
`~/.openclaw/logs/`.

## Design docs

`docs/superpowers/{specs,plans}/` holds dated design/spec markdown for larger
changes (e.g. the niri+DMS VM work). Consult these for the reasoning behind the
desktop setup.
