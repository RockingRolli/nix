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
  split the same way: system prerequisites (overlay, linger, secrets dir, the
  openssl/ffmpeg system packages OpenClaw insists on) vs. the user-scoped
  gateway config. Only `openclaw` imports them. See "openclaw host" below.
- `pkgs/` — package expressions for software not in nixpkgs, pulled in with
  `pkgs.callPackage ../pkgs/<name>.nix { }` from whichever module needs it.
  Not a module layer and not wired into the flake outputs; it exists because a
  few things (currently the Amazing Marvin MCP server) have to be in the
  closure rather than fetched at runtime.

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

### Read the docs in the package, not the website

**Start every openclaw config question here.** OpenClaw ships its complete
documentation — ~1250 markdown files — inside the npm package, so it is already
in the nix store at the exact version this repo has pinned. The published site
lags and still describes removed options; this tree cannot, because it is the
same build as the running gateway.

```
nix eval --raw .#nixosConfigurations.openclaw.pkgs.openclaw-gateway.outPath
# → /nix/store/…-openclaw-gateway-<version>/lib/node_modules/openclaw/docs
```

Worth knowing what is in there: `docs/channels/telegram/` (one page per concern
— access control, rich messages, messaging, media, troubleshooting),
`docs/gateway/config-*.md` (the configuration reference, including
`configuration-examples.md`), `docs/concepts/memory*.md`,
`docs/reference/memory-config.md`, `docs/tools/`, `docs/plugins/`. Every
question answered in the sections below came out of that tree.

Three companion sources for things the docs do not cover:

- **The locked `nix-openclaw` source**, at
  `nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nix-openclaw.outPath'`.
  `nix/generated/openclaw-config-options.nix` there is the authoritative list
  of what this repo can set — check it when `nix flake check` says an option
  "does not exist". `nix/generated/openclaw-runtime-plugins/` holds the locked
  plugin ids and versions.
- **A runtime plugin's `openclaw.plugin.json`** (in the plugin's own store
  path) — its `configSchema` and `uiHints` are the only description of what
  goes under `plugins.entries.<id>.config`, which is untyped on both sides.
- **The plugin's `dist/*.js`** when even that is silent — e.g. exactly which
  config paths and env vars a provider reads, and in what order.

Consequences worth knowing before editing `home/openclaw.nix`:

- The gateway runs with `OPENCLAW_NIX_MODE=1`, so `openclaw plugins install`
  and friends deliberately fail. Plugins are `bundledPlugins` /
  `runtimePlugins` in the nix config plus a rebuild — never imperative.
- `~/.openclaw/openclaw.json` is generated and force-symlinked on activation.
  Hand edits are lost. `programs.openclaw.config` is schema-typed, so a wrong
  key is an eval error, not silently-ignored JSON — **except under
  `channels.<name>`**, see below.
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
install -m600 /dev/stdin /var/lib/openclaw-secrets/amazing-marvin-api-key <<< '<Marvin API token>'
```

`channels.telegram.allowFrom` in `home/openclaw.nix` is the bot's allowlist,
by Telegram user id (from @userinfobot). Anyone not listed is ignored silently,
so a wrong id looks identical to a broken bot. The agent runs shell commands on
request — adding an id there is granting shell access to this box.
`dmPolicy = "allowlist"` is set alongside it deliberately: the upstream default
is `"pairing"`, under which the effective DM allowlist is `allowFrom` *plus*
whatever approvals sit in the runtime pairing store, so access is partly state
no rebuild resets. The two have to move together — `allowlist` with an empty
`allowFrom` is rejected by config validation.

`commands.ownerAllowFrom` is separate and also required. Being in `allowFrom`
grants channel access, not owner authority, and owner-only commands
(`/restart`, `/activation`, config writes) plus exec-approval prompts check the
owner list. It normally bootstraps from the first approved DM pairing — which
cannot happen here, both because `dmPolicy = "allowlist"` means there is no
pairing to approve and because the bootstrap would write into `openclaw.json`,
which this module force-symlinks read-only out of the store. Entries are
channel-qualified (`telegram:<user id>`), not bare numbers.

### The gateway token lives in OpenClaw's secret store

`channels.telegram.tokenFile` reads its file directly, but the **gateway** auth
token does not. `gateway.auth.token` is a store-backed SecretRef
(`source = "store"`, `provider = "default"`, `id = "OPENCLAW_GATEWAY_TOKEN"`),
resolved out of the team-scoped SQLite secret store in `~/.openclaw`. Seed it
once, after the first `sys-pull`:

```
openclaw secrets store set OPENCLAW_GATEWAY_TOKEN \
  --kind secret --value-file /var/lib/openclaw-secrets/gateway-token
systemctl --user restart openclaw-gateway
```

(`--value` is env-kind only; secret-kind entries must come from `--value-file`,
`-` for stdin.) Keep the file: secret-kind store entries are **write-only**, so
`openclaw secrets store get` will not give the value back, and you need it to
pair a browser with the control UI.

Why not `source = "env"`, which is the obvious wiring and what this config used
first: an env SecretRef is only resolvable by a process that has the variable.
nix-openclaw's `programs.openclaw.environment` puts it in the gateway's systemd
unit, so the daemon works — but every `openclaw` CLI invocation runs outside
that unit, and device approval, pairing and probes all die with `gateway.auth.
token is configured as a secret reference but is unavailable in this command
path`. A store ref is readable by any command path. It is also what OpenClaw's
own `setup` provisions.

Two traps that made this hard to see:

- nix-openclaw's env export helper does `if [[ -f "$value" ]]; then value=$(cat
  "$value")`. When the file is missing it exports **the path string itself** as
  the token. So a forgotten secret file yields a running gateway whose token is
  `/var/lib/openclaw-secrets/gateway-token` — no error anywhere.
- `openclaw gateway status` reports the same condition as a mild note (`SecretRef
  is unresolved in this command path; probing without configured auth
  credentials`), not a failure.

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

### Agent identity

There is no top-level `identity` key — it is per agent, at
`agents.entries.main.identity`. `main` is OpenClaw's built-in default agent id
(`DEFAULT_AGENT_ID`), so using that attribute name attaches the identity to the
agent that already exists; any other name creates a second agent and orphans
the first one's sessions and memories.

`identity` derives more than it displays: `ackReaction` comes from
`identity.emoji`, and the group mention patterns come from `name`/`emoji`. The
first of those is a live trap — Telegram only accepts reactions from its own
fixed set, and the configured 🫪 (U+1FAEA) is not in it, so
`channels.telegram.ackReaction` is set explicitly to override the derivation.
`identity.avatar` must be a workspace-relative file, an `http(s)` URL or a
`data:` URI; a placeholder string is a broken path, not an empty field.

### Inline buttons (and why `"dm"` is the wrong scope)

`channels.telegram.capabilities.inlineButtons` takes `off | dm | group | all |
allowlist` (default `allowlist`), and this repo sets `"all"`. `dm` and `group`
are not merely narrower: they add a check that the send target is a **numeric**
chat id and throw `Telegram inline buttons require a numeric chat id` when it
is not, which is how a config that reads correctly produces buttons that never
appear. `all` and `allowlist` skip that check.

Receiving a button and pressing one are authorized separately. A DM callback is
always checked against the DM allowlist (`callback-allowlist` mode), so a bot
whose DM access came only from a pairing approval can render buttons that do
nothing when tapped. That is the second reason `dmPolicy`/`allowFrom` are
explicit.

`richMessages` (Bot API 10.3 typed blocks — tables, checklists, collapsible
sections) is deliberately off: upstream keeps it off because several current
clients render accepted rich messages as "unsupported message".

### Web search: SearXNG

`tools.web.search.provider = "searxng"` plus the runtime plugin; the instance
URL is plugin config at `plugins.entries.searxng.config.webSearch.baseUrl`.
Three things that are not obvious:

- The provider must be named explicitly. Key-free providers never win
  OpenClaw's auto-detection implicitly.
- The SearXNG instance needs `json` under `search.formats` in its
  `settings.yml`. The plugin uses the native `format=json` endpoint, not HTML
  scraping, and an instance without it fails every query.
- `http://` base URLs are only accepted when they resolve to a private or
  loopback address — public hosts must be `https://`. The LAN instance is
  fine; this is why it does not need TLS.

### Memory

Two layers, and they are not alternatives:

- **Built-in** — Markdown in the agent workspace (`MEMORY.md`, `USER.md`,
  `memory/YYYY-MM-DD.md`) indexed for `memory_search`. `memory.search.enabled`
  defaults to **true** and `memory.search.provider` defaults to **`openai`**,
  so on a host with no OpenAI key the vector half is dead by default. Setting
  `provider = "ollama"` is what makes the shipped memory path work at all.
- **LanceDB** — the `memory-lancedb` runtime plugin, claimed via
  `plugins.slots.memory`. Exactly one plugin owns that slot; it supplies
  `memory_store` / `memory_recall` / `memory_forget` and a vector table under
  `~/.openclaw/memory/lancedb`. Inspect it with `openclaw ltm list|search|stats`.

Both embed through the LAN ollama box with `bge-m3:567m` (multilingual, which
matters for German). `embedding.dimensions = 1024` is **required**: OpenClaw
only knows the vector width of OpenAI's two embedding models and throws
"unsupported embedding model" for anything else without it. Changing the model
or dimensions invalidates stored vectors — the built-in index pauses itself and
warns (`openclaw memory index --force` rebuilds), LanceDB does not re-embed at
all and needs its table rebuilt by hand.

Trade-off worth knowing: LanceDB's recall does not get the protected
cross-conversation transcript authorization the built-in provider has, so
`memory.search.rememberAcrossConversations` is skipped while LanceDB owns the
slot. `openclaw doctor` reports this.

### MCP servers

`mcp.servers.<name>`, stdio or HTTP. Two NixOS-specific consequences:

- **Packaging.** `mcp.servers.*.command` has to exist before the gateway
  starts, so a server cannot come from `pipx`/`uvx`, which resolve at runtime.
  `pkgs/` holds the nix expressions for ones not in nixpkgs —
  `amazing-marvin-mcp.nix` is the first.
- **Secrets.** `mcp.servers.*.env` is typed as plain strings and lands verbatim
  in the generated `openclaw.json` in the nix store, i.e. world-readable. The
  pattern here is a `writeShellApplication` wrapper that reads the key from
  `/var/lib/openclaw-secrets` at spawn time and `exec`s the server, same shape
  as the transcription wrapper.

Saving a definition proves nothing; `openclaw mcp doctor <name> --probe` opens
a real connection and lists the tools the server advertises.

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
is reachable at `https://<host-ip>:18789` from the network.
`modules/services/openclaw.nix` opens 18789 to `192.168.178.0/24` only, via
`networking.firewall.extraCommands` (`allowedTCPPorts` cannot express a source
restriction). Four things to know:

- OpenClaw refuses a non-loopback bind without token or password auth, so
  `gateway.auth` is load-bearing, not decoration.
- **https, not http.** The control UI authenticates browsers by device
  identity, which needs a secure context; over plain http to a LAN IP it hangs
  on "device identity required" regardless of the token. Hence
  `gateway.tls.autoGenerate` — self-signed, so expect a one-time cert
  interstitial per browser. The old `controlUi.allowInsecureAuth` escape hatch
  is gone from the schema and had stopped working before that.
- **`openssl` must be in `environment.systemPackages`** or the gateway dies
  generating that cert and never opens the port. See "trusted system
  directories" below.
- Tailscale (`bind = "tailnet"` + `tailscale.mode = "serve"`) or a
  TLS-terminating proxy is the clean version and removes the `tls` block. An
  ssh tunnel to localhost needs none of it — loopback devices auto-approve.

Service: `systemctl --user status openclaw-gateway`, logs at
`~/.openclaw/logs/`.

### "Trusted system directories" — the NixOS trap

OpenClaw 2026.9.x resolves its infrastructure binaries (`openssl`, `ffmpeg`,
`ffprobe`) with a resolver that **ignores `PATH` on purpose** — an
anti-PATH-hijack measure — and searches a fixed list instead. On Linux:
`/usr/bin`, `/bin`, `/usr/sbin`, `/sbin`, `/run/current-system/sw/bin`,
`/snap/bin`. It only tests that the candidate is executable; it does not
resolve symlinks, so a system-profile link into `/nix/store` is fine.

Two consequences:

- The **only** way to satisfy it on NixOS is `environment.systemPackages`, via
  `/run/current-system/sw/bin`. Not `home.packages`, not the nix-openclaw
  wrapper's own runtime PATH, not `programs.openclaw.runtimePackages` — all of
  those are PATH, which the resolver never reads.
- The failure mode is a hard throw, not a degrade: `<name> not found in trusted
  system directories`. For openssl that kills gateway startup during TLS cert
  generation, so `systemctl --user status` shows the unit "active (running)"
  while nothing listens on the port. Check `~/.openclaw/logs/` — the reason is
  only in the log, not in systemd.

If a future release reaches for another system binary, this is the shape of the
bug, and the fix is one more entry in `environment.systemPackages`. nix-openclaw
does not paper over any of this — it carries no openssl handling at all.

**Schema drift is real.** nix-openclaw regenerates
`nix/generated/openclaw-config-options.nix` from upstream OpenClaw, and keys
move or vanish between releases (`gateway.controlUi.allowInsecureAuth` did).
When `nix flake check` reports an option that "does not exist", check the
generated file in the locked input rather than the published docs — the website
lags and still references removed options. The in-package docs tree (see "Read
the docs in the package" above) does not have that problem; it is pinned to the
same release as the gateway.

**`channels` is the one unvalidated block.** It is the only `freeformType =
attrsOf anything` in the generated schema (`channels.defaults` is typed, the
per-channel attrsets are not). So everything under `channels.telegram` —
`tokenFile`, `allowFrom`, `groups` — passes straight through to
`openclaw.json` unchecked, and a misspelled key is silently ignored rather than
an eval error. Cross-check those keys against `docs/channels/<name>/` in the
package, not against `nix flake check`. The same applies to
`plugins.entries.<id>.config`, which is `attrsOf anything` on the nix side and
only described by that plugin's `openclaw.plugin.json`.

**Why the telegram token is a file and the gateway token is not.** Not an
inconsistency: `channels.telegram.tokenFile` is read straight off disk by the
one process that needs it (`tryReadSecretFileSync`, symlinks rejected), by both
the gateway and `openclaw`'s account-inspection paths. It never goes through
the SecretRef resolver, so it has none of the env-ref problem above. It could
be moved to a store-backed `channels.telegram.botToken` SecretRef, but that
would trade a readable, `install`-rotatable file for a write-only store entry
and buy nothing.

## Design docs

`docs/superpowers/{specs,plans}/` holds dated design/spec markdown for larger
changes (e.g. the niri+DMS VM work). Consult these for the reasoning behind the
desktop setup.
