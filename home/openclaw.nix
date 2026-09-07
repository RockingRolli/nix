{ config, pkgs, lib, nix-openclaw, ... }:

# OpenClaw agent, layered on top of home/common.nix for the `openclaw` host
# only. Everything here is user-scoped state under ~/.openclaw; the system-side
# prerequisites (overlay, linger, secrets dir, binary cache) are in
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
  #   install -m600 /dev/stdin /var/lib/openclaw-secrets/telegram-bot-token  <<< '<token from @BotFather>'
  #   install -m600 /dev/stdin /var/lib/openclaw-secrets/anthropic-api-key   <<< '<sk-ant-...>'
  #   openssl rand -hex 32 | install -m600 /dev/stdin /var/lib/openclaw-secrets/gateway-token
  secrets = "/var/lib/openclaw-secrets";

  # Local ollama box on the LAN. Plain http, so keep this to a trusted network.
  ollamaBaseUrl = "http://10.0.0.234:11434";
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

    # Values here are *file paths*, not secrets: the generated gateway wrapper
    # cats the file at startup and exports its contents. (A name ending in
    # _FILE would get the path exported instead.) Nothing reaches the store.
    environment = {
      ANTHROPIC_API_KEY = "${secrets}/anthropic-api-key";
      OPENCLAW_GATEWAY_TOKEN = "${secrets}/gateway-token";
    };

    # Upstream OpenClaw config shape, schema-typed by nix-openclaw — a typo in
    # a key is an eval error rather than a silently ignored JSON field.
    config = {
      gateway = {
        mode = "local";
        # Loopback only. No firewall hole is opened for it; reach the control
        # UI over ssh: `ssh -L 18789:localhost:18789 openclaw`.
        bind = "loopback";
        port = 18789;
        auth = {
          mode = "token";
          token = {
            source = "env";
            provider = "default";
            id = "OPENCLAW_GATEWAY_TOKEN";
          };
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

      models.providers = {
        anthropic.apiKey = {
          source = "env";
          provider = "default";
          id = "ANTHROPIC_API_KEY";
        };

        # Local models. OpenClaw discovers the served tags from the box itself,
        # so no models list is declared here — `openclaw models list` shows what
        # is actually available, and any of them can be picked at runtime as
        # `ollama/<tag>`. timeoutSeconds is raised because a LAN box on CPU can
        # take minutes for a first token.
        ollama = {
          api = "ollama";
          baseUrl = ollamaBaseUrl;
          timeoutSeconds = 600;
        };
      };

      agents.defaults.model = {
        primary = "anthropic/claude-opus-5";
        # Add a local fallback once you know which tag 10.0.0.234 serves, e.g.
        #   fallbacks = [ "ollama/qwen3:8b" ];
        # Left unset on purpose: a fallback pointing at a tag the box does not
        # have fails at request time, not at build time.
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
