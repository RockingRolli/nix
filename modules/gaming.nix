{ config, pkgs, lib, ... }:

# Steam + Proton. Only for bare-metal hosts with a real GPU and a display —
# imported by hosts/laptop.nix. The headless dev VMs and dev-desktop (a guest,
# so no direct GPU) do not import this.
#
# Assumes ../desktop.nix is also imported (pipewire, graphics, portals) — on
# laptop.nix that comes in via ../modules/laptop.nix.
{
  # Steam is unfree. Scoped to exactly the two steam derivations instead of a
  # blanket nixpkgs.config.allowUnfree, so importing this module doesn't
  # silently widen what the rest of the system may pull in. (steam-run,
  # proton-ge-bin, gamescope and mangohud are all free — they need no entry.)
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "steam-unwrapped"
    ];

  programs.steam = {
    enable = true;

    # Proton-GE: community Proton build carrying media codecs and per-game
    # patches Valve's Proton lacks. Appears in the per-game compatibility-tool
    # dropdown as "GE-Proton…" after a client restart.
    extraCompatPackages = [ pkgs.proton-ge-bin ];

    # Winetricks against a Proton prefix, for the occasional title that needs
    # a DLL or registry poke.
    protontricks.enable = true;

    # Firewall deliberately left closed: base.nix opens only 22, and a laptop
    # that joins untrusted networks should not be listening on the Remote Play
    # / game-transfer ports. Set remotePlay.openFirewall or
    # localNetworkGameTransfers.openFirewall to true if those are wanted.
  };

  # gamescope: nested micro-compositor. The payoff on an iGPU is rendering the
  # game at a lower internal resolution and FSR-upscaling to the panel, via a
  # per-game Steam launch option:
  #   gamescope -w 1280 -h 720 -W 1920 -H 1200 -f -F fsr -- %command%
  # programs.steam only pulls gamescope in for gamescopeSession, which we don't
  # use — niri is the session — so enable it explicitly.
  programs.gamescope = {
    enable = true;
    # capSysNice stays off on purpose: it routes gamescope through
    # security.wrappers (a setcap binary), and the kernel strips LD_PRELOAD
    # from those — which is exactly how MangoHud and friends inject. Losing
    # the overlay costs more than the self-renice buys.
    capSysNice = false;
  };

  # gamemode: switches the CPU governor to performance and renices the game for
  # the duration of a run, then puts everything back. Use as a launch option:
  #   gamemoderun %command%
  # Cooperates with power-profiles-daemon (enabled in modules/laptop.nix).
  programs.gamemode.enable = true;

  # hardware/laptop.nix declares `swapDevices = [ ]` — this host has no swap at
  # all. Proton's shader pre-caching forks one compile job per core and each can
  # hold a GB+, and the iGPU carves its framebuffer out of the same system RAM;
  # that combination is the realistic OOM path here. zram is compressed swap in
  # RAM, so it needs no change to the LUKS/partition layout.
  zramSwap.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud # FPS/frametime/temp overlay: `mangohud %command%`
    vulkan-tools # vulkaninfo — first thing to check when a game won't start
  ];
}
