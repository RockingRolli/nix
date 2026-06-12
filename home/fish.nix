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
      user.email = "roland.vonohlen@gmail.com";
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

      # Escape hatch: paste raw fish here as the config evolves.
    '';
  };
}
