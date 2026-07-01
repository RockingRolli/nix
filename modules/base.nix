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
    # for weasyprint/pdf generation
    pango
    cairo
    gdk-pixbuf
    glib
    harfbuzz
    fontconfig
    freetype
    file
  ];

  # mutableUsers=true: passwords are not declared in this repo. The trade-off:
  # this repo no longer owns user state end-to-end — passwords persist in
  # /etc/shadow across rebuilds and won't follow a `nixos-rebuild` to a fresh
  # disk. SSH keys, groups, shell, and home dir are still declarative below.
  users.mutableUsers = true;
  users.users.rvo = {
    isNormalUser = true;
    description = "rvo";
    extraGroups = [ "wheel" "input" "video" ];
    shell = pkgs.fish;
    # TODO: rotate to an ed25519 key (RSA is deprecated and the host label
    # `roland@pwrbox` leaks an internal hostname). Swap to a fresh
    # `ssh-ed25519 ...` line and drop the trailing comment.
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDUigaGiHUDe2sJgGQfx/GFf5pVgNJJCZClwC63LStY2gadNiyI3ehMpoNvDIT2EEJMqsRuVL7NIGYFhj3FVArhf7v0SGhSn/Xp8Rwa2s38lBsoaOf1z5CDp4DxE0VNcGN3wBkw4vfMZAgQbCgQuRoCJ7yTxduFrKgXRJmHcu2S/iXYCEltV5Vkh5HfypW+iPGPEY1Tf8CS89XbmgXOxO+WWb50eIf2Yzy/rwbD7Ur8JEjsNpp8fIPiIY1/r5ADEhh0vManLWEQRVkxmOZ3GvRU0Md5ZfFEAU6kMhrNXWpBWyo0uQQbJAetASf1jI49YTWLl6TKZCbzZbqXasOk/7uJ roland@pwrbox"
    ];
  };

  # General sudo requires a password (defense in depth — a hijacked session
  # can't escalate without it). The specific commands the `system::` just
  # recipes invoke get a NOPASSWD exemption below so day-to-day workflow
  # stays friction-free.
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
      # Permit agent forwarding so a VM can use keys forwarded from the laptop
      # (equals the OpenSSH default; set explicitly to document intent).
      AllowAgentForwarding = true;
    };
  };

  # Container runtime is not chosen here — each host imports exactly one of
  # modules/virtualisation/{podman,docker}.nix. base.nix stays runtime-agnostic.

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

    # Playwright browser for project dev servers.
    ungoogled-chromium
  ];
}
