{ config, pkgs, lib, ... }:

{
  home.stateVersion = lib.mkDefault "26.05";

  home.sessionVariables = {
    EDITOR = "nvim";
    PAGER = "less -R";
  };

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
    };

    interactiveShellInit = ''
        set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border"
        
        tide configure --auto \
                    --style='Rainbow' \
                    --rainbow_prompt_separators='Angled' \
                    --powerline_prompt_heads='Sharp' \
                    --powerline_prompt_tails='Flat' \
                    --powerline_prompt_style='Two lines, character and frame' \
                    --powerline_right_prompt_frame=No \
                    --prompt_colors='True color' \
                    --show_time='24-hour format' \
                    --lean_prompt_height='Two lines' \
                    --prompt_connection=Disconnected \
                    --prompt_connection_andor_frame_color=Light \
                    --prompt_spacing=Sparse \
                    --icons='Many icons' \
                    --transient=No
    '';
  };
}
