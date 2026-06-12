{ config, pkgs, lib, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # nix-ld: lets foreign dynamically-linked binaries (uv-installed Python
  # interpreters, pnpm/npm postinstall blobs, rustup toolchains, vendored
  # debuggers/LSPs) run on NixOS without per-project shell.nix or flakes.
  # This is the load-bearing piece that keeps project repos free of *.nix.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
    libffi
    bzip2
    xz
    ncurses
    readline
    sqlite
    libxml2
    libxslt
    libxcrypt
    glibc
  ];

  users.mutableUsers = false;
  users.users.rvo = {
    isNormalUser = true;
    description = "rvo";
    extraGroups = [ "wheel" "podman" ];
    shell = pkgs.fish;
    # REPLACE this before deploying. Empty list + the allowNoPasswordLogin
    # escape hatch below lets the flake evaluate for review, but you cannot
    # actually log in until a real key lands here.
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... rvo@laptop"
    ];
  };
  # Suppresses the "neither root nor any wheel user has a password or key"
  # assertion so `nix flake check` passes against the empty key list above.
  # Once you add a real key, this becomes a no-op (the assertion stops firing).
  users.allowNoPasswordLogin = true;
  security.sudo.wheelNeedsPassword = false;

  # System-level fish enable so vendor completions install correctly.
  # Per-user fish config lives in home/fish.nix.
  programs.fish.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  networking.useDHCP = lib.mkDefault true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  time.timeZone = lib.mkDefault "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  environment.systemPackages = with pkgs; [
    git
    curl
    wget
    htop
    tmux
    rsync
    file
    unzip
    age
    # agenix CLI is best invoked on demand: `nix run github:ryantm/agenix -- -e secret.age`
  ];
}
