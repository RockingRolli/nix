{ config, pkgs, lib, claude-code-nix, ... }:

{
  home.stateVersion = lib.mkDefault "26.05";

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less -R";
  };

  home.sessionPath = [ "${config.home.homeDirectory}/.local/share/pnpm/bin" ];

  # User-scope dev tooling. Lives here so it travels with the user, not the host.
  # uv-installed Python interpreters and rustup toolchains rely on nix-ld at the
  # system level (see modules/base.nix).
  home.packages = (with pkgs; [
    uv
    nodejs_22
    pnpm
    rustup

    go-task

    vim
    ripgrep
    lazygit
    fd
    bat
    eza
    jq
    yq-go
    gh
    delta
    fzf
    zoxide
    direnv
  ]) ++ [
    claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  programs.zellij.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user.name = "rvo";
      user.email = "roland@rvo-host.net";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf.enable = true;
  programs.zoxide.enable = true;
  programs.mise.enable = true;

  # Agent forwarding to the trusted dev VMs. The origin agent (holding the
  # keys) is provided by the laptop's desktop; this only opts the client in.
  # Scoped to named hosts, never `*` — a forwarded agent lets whoever controls
  # the target host use your keys for the life of the connection. This config
  # also runs *inside* the VMs, so scoping prevents blind onward forwarding.
  # Rename hosts to match your ~/.ssh/config aliases if they differ.
  #
  # `settings` attr names are `Host` patterns. enableDefaultConfig is turned off
  # and its old defaults pinned under "*" explicitly (per the home-manager
  # module docs) so no deprecation warnings fire on rebuild.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
      "proj-api tepavi-dev dev-desktop".ForwardAgent = true;
    };
  };

  programs.fish = {
    enable = true;

    plugins = [
      { name = "fzf-fish";  src = pkgs.fishPlugins.fzf-fish.src; }
      { name = "autopair";  src = pkgs.fishPlugins.autopair.src; }
      { name = "tide";      src = pkgs.fishPlugins.tide.src; }
    ];

    shellAbbrs = {
      g  = "git";
      gs = "git status";
      gd = "git diff";
      gl = "git log --oneline --graph --decorate";
      gp = "git pull";
      gP = "git push";
      gc = "git commit";
      gco = "git checkout";

      ll = "eza -lah --git";
      lt = "eza --tree --level=2";

      k = "kubectl";

      v = "vim";

      # System management. Abbreviations, so the real nh command expands onto
      # the prompt and stays editable, with nh's completions taking over.
      sys-pull = "nh os switch --refresh";
      sys-test = "nh os test --refresh";
      sys-rollback = "nh os rollback";
      sys-gc = "nh clean all --keep-since 7d --optimise";

      # Dev machines only; need a clone. sys-local builds the working tree
      # instead of github, for in-progress work — the host is picked from
      # `hostname`, so this is the same abbreviation everywhere. Flakes only see
      # tracked files, so `git add` new ones first.
      sys-local = "nh os switch ${config.home.homeDirectory}/dev/nix";
      sys-update = "nix flake update --flake ${config.home.homeDirectory}/dev/nix";
    };

    shellAliases = {
      cat = "bat --paging=always";
    };

    functions = {
      mkcd = ''
        mkdir -p $argv[1]
        and cd $argv[1]
      '';

      # d / dc are runtime-aware so this one shared config works on both podman
      # and docker hosts. podman is the default runtime AND ships a `docker`
      # compat shim, so testing for `docker` would match everywhere — instead
      # prefer podman when present (every host except the docker ones, where
      # podman is disabled and absent) and fall back to docker.
      d = ''
        if command -q podman
            podman $argv
        else
            docker $argv
        end
      '';

      dc = ''
        if command -q podman
            podman compose $argv
        else
            docker compose $argv
        end
      '';

    };

    interactiveShellInit =
      let
        # tide preset args. Edit freely — the hash below is derived from this
        # string, so any change here invalidates the sentinel and triggers
        # exactly one re-configure on the next shell.
        tideArgs = ''
          --style='Rainbow'
          --rainbow_prompt_separators='Angled'
          --powerline_prompt_heads='Sharp'
          --powerline_prompt_tails='Flat'
          --powerline_prompt_style='Two lines, character and frame'
          --powerline_right_prompt_frame=No
          --prompt_colors='True color'
          --show_time='24-hour format'
          --lean_prompt_height='Two lines'
          --prompt_connection=Disconnected
          --prompt_connection_andor_frame_color=Light
          --prompt_spacing=Sparse
          --icons='Many icons'
          --transient=No
        '';
        tideArgsFlat = builtins.replaceStrings [ "\n" ] [ " " ] tideArgs;
        cfgHash = builtins.substring 0 12 (builtins.hashString "sha256" tideArgs);
      in
      ''
        set fish_greeting

        set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border"

        # Apply tide preset only when the nix-side args have actually changed.
        # `exec fish` lets the next process start with the new universal vars
        # already in place, so the first prompt is rendered correctly without
        # the "press Enter to refresh" bug.
        if functions -q tide; and test "$_tide_cfg_hash" != "${cfgHash}"
            tide configure --auto ${tideArgsFlat}
            set -Ux _tide_cfg_hash "${cfgHash}"
            exec fish
        end
      '';
  };
}
