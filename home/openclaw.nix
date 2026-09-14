{ config, pkgs, lib, nix-openclaw, claude-code-nix, ... }:

# OpenClaw agent, layered on top of home/common.nix for the `openclaw` host
# only. Everything here is user-scoped state under ~/.openclaw; the system-side
# prerequisites (overlay, linger, secrets dir, firewall, binary cache) are in
# modules/services/openclaw.nix.
#
# Upstream packaging notes that shaped this file:
#   - openclaw is not in nixpkgs; nix-openclaw is the only packaging, so the
#     flake input is not optional.
#   - the gateway runs with OPENCLAW_NIX_MODE=1, which makes `openclaw plugins
#     install/update/uninstall` fail on purpose. Plugins are added here and
#     applied with a rebuild, never imperatively.
#   - `openclaw.json` is generated from `config` below and symlinked into
#     ~/.openclaw. Do not hand-edit it; it is overwritten on every activation.

let
  # Runtime-only secret files. The directory is created by
  # modules/services/openclaw.nix; the contents are written once, by hand, and
  # then survive rebuilds — same reasoning as user passwords in base.nix.
  #
  #   install -m600 /dev/stdin /var/lib/openclaw-secrets/telegram-bot-token <<< '<token from @BotFather>'
  #   openssl rand -hex 32 | install -m600 /dev/stdin /var/lib/openclaw-secrets/gateway-token
  #   install -m600 /dev/stdin /var/lib/openclaw-secrets/amazing-marvin-api-key <<< '<Marvin Settings → API token>'
  #
  # Only telegram-bot-token is read from here by config (channels.telegram
  # below). gateway-token is *not* wired in: the gateway token lives in
  # OpenClaw's own secret store and is seeded from that file once (see
  # gateway.auth). Keep the file anyway — secret-kind store entries are
  # write-only, so it is the only readable copy of the value you need to paste
  # into the control UI. amazing-marvin-api-key is read by the MCP wrapper
  # below, not by OpenClaw: `mcp.servers.*.env` is plain strings in the
  # generated openclaw.json, i.e. world-readable in the nix store.
  #
  # No anthropic-api-key: Claude runs through the subscription-backed CLI, see
  # agents.defaults.models below.
  secrets = "/var/lib/openclaw-secrets";

  # Local ollama box on the LAN. Plain http, so keep this to a trusted network.
  ollamaBaseUrl = "http://10.0.0.234:11434";

  # Embeddings for both memory paths (built-in memory.search and the LanceDB
  # plugin) come off the same ollama box. bge-m3 is multilingual, which matters
  # because half the traffic here is German — nomic-embed-text is also served
  # but is English-first. 1024 is bge-m3's vector width and has to be declared:
  # OpenClaw only knows the dimensions of OpenAI's two embedding models, and
  # anything else without an explicit `dimensions` is a hard "unsupported
  # embedding model" error.
  #
  # Changing either value invalidates the stored vectors. The built-in index
  # pauses itself and warns (rebuild with `openclaw memory index --force`);
  # LanceDB does *not* re-embed and needs its table rebuilt by hand.
  embedModel = "bge-m3:567m";
  embedDimensions = 1024;

  # Self-hosted SearXNG, used as the web_search provider. Its instance needs
  # `json` in `search.formats` in settings.yml or every query fails; this one
  # already answers /search?q=…&format=json. Plain http is fine *because* the
  # host is a private address — the plugin rejects http:// base URLs that
  # resolve publicly.
  searxngBaseUrl = "http://192.168.178.149:8888";

  claudeCode = claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Amazing Marvin task manager, exposed to the agent over MCP. Packaged in
  # ../pkgs because it is not in nixpkgs; upstream's install path is pipx/uvx,
  # which resolves wheels at runtime and would leave the gateway starting a
  # server that may or may not exist.
  #
  # The wrapper exists for the API key: `mcp.servers.<n>.env` is typed as plain
  # strings and lands verbatim in the generated openclaw.json under the nix
  # store, so the key is read from the runtime secrets dir at spawn time
  # instead. writeShellApplication's `set -u`/`-e` means a missing secret file
  # is a loud failure rather than an empty key — worth having, given
  # nix-openclaw's own env helper silently exports the *path* when the file is
  # absent (see the note on `environment` below).
  #
  # The two FASTMCP_ variables turn off fastmcp's startup banner and its
  # version check, which otherwise hits pypi.org on every single spawn.
  marvinMcp = pkgs.callPackage ../pkgs/amazing-marvin-mcp.nix { };

  marvin = pkgs.writeShellApplication {
    name = "openclaw-amazing-marvin-mcp";
    runtimeInputs = [
      marvinMcp
      pkgs.coreutils
    ];
    text = ''
      AMAZING_MARVIN_API_KEY="$(cat ${secrets}/amazing-marvin-api-key)"
      export AMAZING_MARVIN_API_KEY
      export FASTMCP_CHECK_FOR_UPDATES=off
      export FASTMCP_SHOW_SERVER_BANNER=false
      exec amazing-marvin-mcp
    '';
  };

  # whisper.cpp ggml model. `small` is the sweet spot for German voice notes on
  # CPU — `base` mishears too much, `medium` is ~5x slower for little gain.
  whisperModel = "small";

  # Transcription for inbound voice messages. OpenClaw calls an external
  # command and takes its stdout as the transcript, so this wrapper has to
  # print the text and nothing else.
  #
  # The ggml weights are ~500MB and are not in nixpkgs, so they are fetched
  # once into the user cache on first use — runtime state, like the secrets
  # above and like DMS's ~/.config/niri on dev-desktop. nixpkgs patches
  # upstream's download script to write into $PWD, hence the subshell cd.
  transcribe = pkgs.writeShellApplication {
    name = "openclaw-transcribe";
    runtimeInputs = [
      pkgs.whisper-cpp
      pkgs.ffmpeg
      pkgs.coreutils
    ];
    text = ''
      model_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/whisper-cpp"
      model_file="$model_dir/ggml-${whisperModel}.bin"

      if [ ! -f "$model_file" ]; then
        mkdir -p "$model_dir"
        ( cd "$model_dir" && whisper-cpp-download-ggml-model ${whisperModel} ) >&2
      fi

      # Telegram voice notes are opus in ogg; feed whisper the 16kHz mono wav
      # it wants rather than relying on its optional ffmpeg decode path.
      wav="$(mktemp --suffix=.wav)"
      trap 'rm -f "$wav"' EXIT
      ffmpeg -nostdin -loglevel error -y -i "$1" -ar 16000 -ac 1 -c:a pcm_s16le "$wav" >&2

      # -l auto: German and English voice notes both work.
      # -nt/-np: transcript only, no timestamps and no progress chatter.
      whisper-cli -m "$model_file" -f "$wav" -l auto -nt -np
    '';
  };
in
{
  imports = [ nix-openclaw.homeManagerModules.openclaw ];

  programs.openclaw = {
    # `instances.default` instead of the simpler `enable = true`: as soon as
    # `instances` is non-empty it replaces the implicit default instance, and
    # it is the only place logPath can be overridden. The module default puts
    # the log in /tmp/openclaw/, which is created at activation but not
    # recreated at boot — a restart after reboot would then fail on
    # StandardOutput=append:. Keeping it under ~/.openclaw avoids that.
    instances.default = {
      enable = true;
      logPath = "${config.home.homeDirectory}/.openclaw/logs/gateway.log";
    };

    # The gateway wrapper builds its own PATH and does not inherit the user
    # profile, so the Claude CLI has to be named explicitly here — without it
    # the claude-cli runtime below has nothing to exec.
    runtimePackages = [ claudeCode ];

    # Official OpenClaw npm plugins, pinned and built by nix-openclaw from
    # nix/generated/openclaw-runtime-plugins/. This is the *only* way to add
    # them here: OPENCLAW_NIX_MODE=1 makes `openclaw plugins install` fail on
    # purpose, and the module asserts that an id listed here is not disabled or
    # denied elsewhere in `config.plugins`. It also writes
    # `plugins.entries.<id>.enabled = true` for each id, so the entries below
    # only carry `config`.
    #
    #   searxng        — web_search provider, see tools.web.search
    #   memory-lancedb — long-term memory store, see plugins.slots.memory
    #
    # `openclaw plugins list` on the box shows what actually loaded; a plugin
    # that failed to load is only visible there and in ~/.openclaw/logs/.
    runtimePlugins = [
      "searxng"
      "memory-lancedb"
    ];

    # No `environment` block on purpose. It used to carry
    # OPENCLAW_GATEWAY_TOKEN = "${secrets}/gateway-token", which the generated
    # wrapper cats at startup — but that only ever populated the *gateway
    # process*. Every `openclaw` CLI invocation runs outside the unit with no
    # such variable, and an env-sourced SecretRef cannot be resolved from
    # anywhere else, so device approval and pairing failed with "configured as
    # a secret reference but is unavailable in this command path". The token is
    # store-backed now (see gateway.auth below), which any command path can
    # resolve. Worse, nix-openclaw's export helper only reads the file when it
    # exists — a missing file silently exported the *path string itself* as the
    # token.
    #
    # Deliberately no ANTHROPIC_API_KEY either: if it were set, the Claude CLI
    # would silently switch from the subscription to pay-as-you-go API billing.

    # Upstream OpenClaw config shape, schema-typed by nix-openclaw — a typo in
    # a key is an eval error rather than a silently ignored JSON field.
    config = {
      gateway = {
        mode = "local";
        # Reachable from the LAN, not just localhost. OpenClaw refuses to start
        # a non-loopback bind without token or password auth, which is what the
        # auth block below provides. Port 18789 is opened in
        # modules/services/openclaw.nix — keep the two in sync.
        bind = "lan";
        port = 18789;
        # Store-backed SecretRef, not env-backed. OpenClaw keeps a team-scoped
        # secret store in the SQLite state DB under ~/.openclaw, and a "store"
        # ref resolves by reading it — so the gateway *and* every CLI command
        # path get the token without anything being exported into a shell.
        # This is what OpenClaw's own `setup` provisions; source = "env" only
        # ever works for the process that has the variable.
        #
        # provider = "default" is the built-in alias for the store source; no
        # entry under `secrets.providers` is needed for it. The id has to match
        # /^[A-Z][A-Z0-9_]{0,127}$/.
        #
        # The value is runtime state written once, same stance as the secrets
        # files — see CLAUDE.md for the `openclaw secrets store set` command.
        # Nothing here reaches the nix store.
        auth = {
          mode = "token";
          token = {
            source = "store";
            provider = "default";
            id = "OPENCLAW_GATEWAY_TOKEN";
          };
        };
        # Self-signed TLS, generated by OpenClaw into the state dir on first
        # start. Not cosmetic: the control UI authenticates a browser by device
        # identity, and the browser APIs that implements are only available in a
        # secure context — https, or plain http to localhost. Over http to a LAN
        # IP the UI gets stuck on "device identity required" no matter what the
        # token says. (`controlUi.allowInsecureAuth` used to paper over this and
        # is gone from the schema; it had stopped working before that.)
        #
        # Cost: browsers show the usual untrusted-cert interstitial once per
        # browser. Clicking through grants the secure context, so pairing works.
        # The clean version of this is Tailscale — `bind = "tailnet"` plus
        # `tailscale.mode = "serve"` gets real certs — or a reverse proxy that
        # terminates TLS. Either way this block is what goes away.
        #
        # Fallback that needs none of it: `ssh -L 18789:localhost:18789 openclaw`
        # and open localhost, which is auto-approved.
        tls = {
          enabled = true;
          autoGenerate = true;
        };
      };

      # Reminder before touching anything here: `channels` is the one block
      # nix-openclaw does *not* type-check (it is the schema's only
      # `freeformType = attrsOf anything`). A misspelled key below is silently
      # dropped into openclaw.json, not an eval error. Cross-check against
      # upstream's docs/channels/telegram/, which ship inside the openclaw npm
      # package itself.
      channels.telegram = {
        tokenFile = "${secrets}/telegram-bot-token";
        # rvo's Telegram user id (from @userinfobot). This is an allowlist:
        # everything not in it is ignored by the bot, so a wrong or empty list
        # means silence rather than an error. Add ids here to let more people
        # talk to the agent — it runs shell commands on request, so treat this
        # as the access control it is.
        allowFrom = [ 611056438 ];

        # Explicit, rather than leaning on the "pairing" default. Under
        # `pairing` the effective DM allowlist is allowFrom *plus* whatever
        # approvals happen to sit in the pairing store, so who can talk to the
        # bot is partly runtime state that no rebuild resets. `allowlist` makes
        # the list above the whole answer. Upstream recommends exactly this for
        # one-owner bots. (A `dmPolicy = "allowlist"` with an empty allowFrom
        # is rejected by config validation, so the two must move together.)
        dmPolicy = "allowlist";
        # Default anyway, stated so the group side is as legible as the DM
        # side: groups are blocked unless listed below.
        groupPolicy = "allowlist";
        # `groups` is the group allowlist and "*" allows any group the bot is
        # added to — but `groupAllowFrom` is unset, which makes group senders
        # fall back to `allowFrom`, so only rvo can actually trigger it.
        # Mention required in groups; direct messages always go through.
        groups."*".requireMention = true;

        # Inline keyboards (`ask_user`'s single-select, exec-approval buttons,
        # and `send` with a `buttons` presentation block).
        #
        # Scopes are off | dm | group | all | allowlist (default). "all" rather
        # than "dm": `dm` and `group` are not just narrower, they add a check
        # that the send target is a *numeric* chat id and throw "inline buttons
        # require a numeric chat id" otherwise — which is how a config that
        # looks correct ends up with buttons that never appear. "all" and
        # "allowlist" skip that check entirely.
        #
        # Pressing a button is authorized separately from receiving one: a DM
        # callback is always checked against the DM allowlist. That is the
        # other half of why dmPolicy/allowFrom above are explicit.
        capabilities.inlineButtons = "all";

        # Telegram only accepts reactions from its own fixed set. Without this,
        # the ack reaction is derived from `identity.emoji` below — and 🫪
        # (U+1FAEA) is not in that set, so Telegram would reject it. Only fires
        # in groups by default (`messages.ackReactionScope` defaults to
        # "group-mentions"); set that to "direct" or "all" to get it in DMs.
        ackReaction = "👀";

        # Not enabled: `richMessages = true` opts into Bot API 10.3 typed
        # blocks (tables, checklists, collapsible sections, formulas). Upstream
        # keeps it off because several current clients render them as
        # "unsupported message". Worth trying from a single client.
      };

      # Owner identity for privileged commands (`/restart`, `/activation`,
      # config writes) and for exec-approval prompts. Being in
      # channels.telegram.allowFrom is explicitly *not* enough — that grants
      # channel access, not owner authority.
      #
      # Normally this bootstraps itself from the first approved DM pairing,
      # which cannot happen here for two reasons: dmPolicy is "allowlist", so
      # there is no pairing to approve; and the bootstrap writes into
      # openclaw.json, which this module force-symlinks read-only out of the
      # nix store. So it has to be declared. Same id as allowFrom, but
      # channel-qualified — bare numbers are not accepted here.
      commands.ownerAllowFrom = [ "telegram:611056438" ];

      # Local models. OpenClaw discovers the served tags from the box itself,
      # so no models list is declared here — `openclaw models list` shows what
      # is actually available, and any of them can be picked at runtime as
      # `ollama/<tag>`. timeoutSeconds is raised because a LAN box on CPU can
      # take minutes for a first token.
      models.providers.ollama = {
        api = "ollama";
        baseUrl = ollamaBaseUrl;
        timeoutSeconds = 600;
      };

      agents.defaults = {
        model = {
          primary = "anthropic/claude-opus-5";
          # Add a local fallback once you know which tag 10.0.0.234 serves, e.g.
          #   fallbacks = [ "ollama/qwen3:8b" ];
          # Left unset on purpose: a fallback pointing at a tag the box does not
          # have fails at request time, not at build time.
        };

        # Subscription, not API key. Anthropic blocks subscription OAuth for
        # third-party apps, and the one sanctioned path is reusing a Claude
        # Code login on the same host: the model reference stays canonical
        # `anthropic/*` and only the execution backend changes. Requires a
        # one-time interactive `claude` login as rvo on this box — see CLAUDE.md.
        models."anthropic/claude-opus-5".agentRuntime.id = "claude-cli";
      };

      # Identity is per agent, not global — there is no top-level `identity`
      # key. "main" is OpenClaw's built-in default agent id, so this attaches
      # to the agent that already exists rather than creating a second one;
      # renaming the attribute would orphan its sessions and memories.
      #
      # `identity` also derives two things it does not look like it derives:
      # the ack reaction (overridden per channel above, because Telegram will
      # not take this emoji) and the group mention patterns, so the agent
      # answers to "Humble Messenger" and to the emoji in groups, not only to
      # @botusername.
      #
      # No `avatar`: it must be a workspace-relative file, an http(s) URL or a
      # data: URI. A placeholder string is a broken path, not an empty field.
      agents.entries.main.identity = {
        name = "Humble Messenger";
        emoji = "🫪";
        theme = "AI assistant (no costume — a straight assistant that carries messages and gets things done)";
      };

      # Built-in memory: the Markdown files in the agent workspace (MEMORY.md,
      # USER.md, memory/YYYY-MM-DD.md) indexed for `memory_search`.
      #
      # This is not optional tuning. `memory.search.enabled` defaults to true
      # and `provider` defaults to "openai", so on a host with no OpenAI key
      # every search silently falls back or fails. Pointing it at the ollama
      # box is what makes the default memory path work at all. Keyword search
      # keeps working regardless; it is the vector half that needs embeddings.
      #
      # sqlite-vec acceleration is bundled and degrades to in-process cosine
      # similarity if it cannot load, so it needs nothing from NixOS.
      memory.search = {
        provider = "ollama";
        model = embedModel;
      };

      plugins = {
        # Exactly one plugin owns the memory slot. Claiming it here replaces
        # the built-in memory *store* with LanceDB and swaps the agent's
        # memory tools for the plugin's memory_store / memory_recall /
        # memory_forget. The Markdown workspace files and `memory.search`
        # above stay as they are — the two layers coexist.
        #
        # Known trade-off: LanceDB's recall does not get the protected
        # cross-conversation transcript authorization that the built-in
        # provider has, so `memory.search.rememberAcrossConversations` is
        # skipped while LanceDB owns the slot. `openclaw doctor` says so.
        slots.memory = "memory-lancedb";

        # Per-plugin settings. Each id here is also listed in runtimePlugins
        # above, which is what supplies `enabled = true` and the load path.
        # This block is `attrsOf anything` in the schema — like `channels`, a
        # typo is silent. Each plugin validates its own config at load time and
        # reports into ~/.openclaw/logs/.
        entries = {
          searxng.config.webSearch = {
            baseUrl = searxngBaseUrl;
            # categories/language left unset: default is "general", and a
            # non-general category that returns nothing is retried as general
            # anyway. Pinning `language` would bias mixed DE/EN queries.
          };

          "memory-lancedb".config = {
            # Provider-adapter path: `provider` names one of OpenClaw's own
            # embedding adapters, which then follows the ollama provider's
            # base-URL rules. (The other path — omit `provider`, set apiKey +
            # baseUrl — is for raw OpenAI-compatible endpoints.) baseUrl is
            # repeated here because the box is remote, not localhost.
            embedding = {
              provider = "ollama";
              baseUrl = ollamaBaseUrl;
              model = embedModel;
              dimensions = embedDimensions;
            };
            # Recall automatically, store only on request. With autoCapture
            # off the agent still writes memories — it just has to call
            # memory_store deliberately ("remember that …") instead of a
            # trigger-phrase heuristic deciding for it, up to 3 per turn.
            # Turn it on once recall has proved itself; the stored rows are
            # otherwise only visible through `openclaw ltm list`.
            autoRecall = true;
            autoCapture = false;
            # Below the 1000 default: bge-m3 caps at 8192 tokens, but a long
            # recall query embeds slowly on a CPU box for little gain.
            recallMaxChars = 600;
          };
        };
      };

      # Amazing Marvin task tools, over stdio. `command` is the secret-reading
      # wrapper from the let block, so nothing sensitive reaches openclaw.json.
      #
      # Verify with `openclaw mcp doctor amazing-marvin --probe` — saving a
      # definition proves nothing, the probe opens a real connection and lists
      # the tools. Its tools go through the normal tool policy like any other.
      mcp.servers.amazing-marvin = {
        transport = "stdio";
        command = lib.getExe marvin;
        enabled = true;
      };

      tools = {
        # Voice notes in, text out. Without an explicit model OpenClaw would
        # auto-detect (reply model → cloud provider creds → local CLIs);
        # pinning the CLI keeps audio local and off the subscription's quota.
        media = {
          models = [
            {
              type = "cli";
              command = "${lib.getExe transcribe}";
              args = [ "{{AttachmentPath}}" ];
              capabilities = [ "audio" ];
              timeoutSeconds = 300;
            }
          ];
          audio = {
            enabled = true;
            # Echo what was understood — a wrong transcript is otherwise
            # invisible until the agent answers the wrong question.
            echoTranscript = true;
          };
        };

        # web_search through the LAN SearXNG box; the instance URL is plugin
        # config, under plugins.entries.searxng below.
        #
        # `provider` is explicit on purpose. SearXNG never wins OpenClaw's
        # provider auto-detection implicitly — key-free providers only activate
        # on an explicit choice — so without this the agent would either have
        # no search or reach for a cloud provider.
        web.search = {
          enabled = true;
          provider = "searxng";
        };
      };
    };

    # nix-openclaw's own tool plugins (screenshots, TTS, iMessage, …) are
    # mostly macOS-facing; `summarize` is the useful headless one. Each enabled
    # plugin is another flake source to build, so they stay off until wanted:
    #   bundledPlugins.summarize.enable = true;
    #
    # Gateway-side runtime plugins (Discord, Slack, …) go in
    # `runtimePlugins = [ "discord" ];` and are configured under `config.channels`.
    #
    # The agent's identity documents (AGENTS.md, SOUL.md, TOOLS.md,
    # IDENTITY.md, USER.md) can be made declarative with
    # `workspace.bootstrapFiles`. Unset here, so OpenClaw seeds its own
    # templates into ~/.openclaw/workspace and owns them as runtime state.
  };

  systemd.user.services.openclaw-gateway = {
    # nix-openclaw emits the unit but no [Install] section, so nothing wants it
    # at login and a lingering session would never start it. This is what makes
    # the bot come back on its own after a reboot.
    Install.WantedBy = [ "default.target" ];

    # Both flagged by `openclaw gateway status` as service config issues.
    # KillMode=mixed sends SIGTERM to the main process only, so an in-flight
    # agent turn drains instead of having its children killed underneath it;
    # systemd's default (control-group) kills the lot at once. RestartSec is
    # upstream's recommendation, mkForce because nix-openclaw hardcodes 1s.
    Service = {
      KillMode = "mixed";
      RestartSec = lib.mkForce "5s";
    };
  };
}
