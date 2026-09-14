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
  #
  # No anthropic-api-key: Claude runs through the subscription-backed CLI, see
  # agents.defaults.models below.
  secrets = "/var/lib/openclaw-secrets";

  # Local ollama box on the LAN. Plain http, so keep this to a trusted network.
  ollamaBaseUrl = "http://10.0.0.234:11434";

  claudeCode = claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;

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

    # Values here are *file paths*, not secrets: the generated gateway wrapper
    # cats the file at startup and exports its contents. (A name ending in
    # _FILE would get the path exported instead.) Nothing reaches the store.
    #
    # Deliberately no ANTHROPIC_API_KEY: if it were set, the Claude CLI would
    # silently switch from the subscription to pay-as-you-go API billing.
    environment = {
      OPENCLAW_GATEWAY_TOKEN = "${secrets}/gateway-token";
    };

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
        auth = {
          mode = "token";
          token = {
            source = "env";
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

      channels.telegram = {
        tokenFile = "${secrets}/telegram-bot-token";
        # REPLACE: your Telegram user id, from @userinfobot. Everything not in
        # this list is ignored by the bot, so an empty/wrong list means silence.
        allowFrom = [ 123456789 ];
        # Groups must @mention the bot; direct messages always go through.
        groups."*".requireMention = true;
      };

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

      # Voice notes in, text out. Without an explicit model OpenClaw would
      # auto-detect (reply model → cloud provider creds → local CLIs); pinning
      # the CLI keeps audio local and off the subscription's quota.
      tools.media = {
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
          # Echo what was understood — a wrong transcript is otherwise invisible
          # until the agent answers the wrong question.
          echoTranscript = true;
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

  # nix-openclaw emits the unit but no [Install] section, so nothing wants it
  # at login and a lingering session would never start it. This is what makes
  # the bot come back on its own after a reboot.
  systemd.user.services.openclaw-gateway.Install.WantedBy = [ "default.target" ];
}
