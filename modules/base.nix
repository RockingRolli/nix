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
    extraGroups = [ "wheel" "podman" "input" "video" ];
    shell = pkgs.fish;
    # REPLACE this before deploying. Empty list + the allowNoPasswordLogin
    # escape hatch below lets the flake evaluate for review, but you cannot
    # actually log in until a real key lands here.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUigaGiHUDe2sJgGQfx/GFf5pVgNJJCZClwC63LStY2gadNiyI3ehMpoNvDIT2EEJMqsRuVL7NIGYFhj3FVArhf7v0SGhSn/Xp8Rwa2s38lBsoaOf1z5CDp4DxE0VNcGN3wBkw4vfMZAgQbCgQuRoCJ7yTxduFrKgXRJmHcu2S/iXYCEltV5Vkh5HfypW+iPGPEY1Tf8CS89XbmgXOxO+WWb50eIf2Yzy/rwbD7Ur8JEjsNpp8fIPiIY1/r5ADEhh0vManLWEQRVkxmOZ3GvRU0Md5ZfFEAU6kMhrNXWpBWyo0uQQbJAetASf1jI49YTWLl6TKZCbzZbqXasOk/7uJ roland@pwrbox"
    ];
  };
  # Suppresses the "neither root nor any wheel user has a password or key"
  # assertion so `nix flake check` passes against the empty key list above.
  # Once you add a real key, this becomes a no-op (the assertion stops firing).
  users.allowNoPasswordLogin = false;

  # Temporarily passwordless while iterating on the desktop. The targeted
  # NOPASSWD rules below remain in place but become no-ops; they're kept so
  # tightening back to "real password for general sudo + NOPASSWD for the
  # day-to-day commands" is a one-line change (delete this attribute).
  security.sudo.wheelNeedsPassword = false;

  # General sudo still requires a password (defense in depth — a hijacked
  # session can't escalate without the password). The specific commands the
  # `system::` just recipes invoke get a NOPASSWD exemption below so day-to-day
  # workflow stays friction-free.
  security.sudo.extraRules = [{
    users = [ "rvo" ];
    commands = [
      { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" "SETENV" ]; }
      { command = "/run/current-system/sw/bin/nix-collect-garbage"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-store"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/reboot"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/shutdown"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/poweroff"; options = [ "NOPASSWD" ]; }
    ];
  }];

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
  console.keyMap = "de";

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
