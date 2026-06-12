{ config, pkgs, lib, ... }:

{
  home.stateVersion = lib.mkDefault "26.05";

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less -R";
  };

  # Global justfile + its modules, deployed to ~/.config/just/ where
  # `just --global-justfile` (a.k.a. `just -g`) looks for them.
  xdg.configFile."just/justfile".source = ./justfile;
  xdg.configFile."just/tasks/system.just".source = ./tasks/system.just;

  # User-scope dev tooling. Lives here so it travels with the user, not the host.
  # uv-installed Python interpreters and rustup toolchains rely on nix-ld at the
  # system level (see modules/base.nix).
  home.packages = with pkgs; [
    uv
    nodejs_22
    pnpm
    rustup

    neovim
    ripgrep
    fd
    bat
    eza
    jq
    yq-go
    just
    gh
    delta
    fzf
    zoxide
    direnv
    btop
  ];

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
      d = "podman";
      dc = "podman compose";

      v = "nvim";
    };

    shellAliases = {
      cat = "bat --paging=never";
    };

    functions = {
      mkcd = ''
        mkdir -p $argv[1]
        and cd $argv[1]
      '';

      # Wraps `just` so it picks the local justfile if one exists anywhere
      # in the directory ancestry (matching just's own search behaviour),
      # otherwise falls back to the global one at ~/.config/just/justfile.
      # Lets `just system::pull` work from any directory.
      just = ''
        set -l dir $PWD
        while test "$dir" != /
            if test -f "$dir/justfile"; or test -f "$dir/Justfile"; or test -f "$dir/.justfile"
                command just $argv
                return $status
            end
            set dir (dirname "$dir")
        end
        command just --global-justfile $argv
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
