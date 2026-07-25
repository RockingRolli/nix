{ config, pkgs, lib, ... }:

# Memory + build-scheduling tuning for an interactive workstation. Opt-in: a
# host imports this when it has a human sitting in front of it and cares more
# about staying responsive than about finishing a rebuild 20% sooner. The
# headless dev VMs deliberately do not import it — they want every core.
#
# The parallelism numbers below assume roughly 8C/16T and >=16 GB RAM (the
# ThinkPad T14s Gen4). Re-check them before importing this on a smaller host.
{
  # ---------------------------------------------------------------- memory --
  # hosts/hardware/laptop.nix declares `swapDevices = [ ]`, so without this the
  # machine has no swap of any kind: the first time an LSP, a container build
  # and a Playwright run overlap, systemd-oomd starts killing things. zram is
  # compressed swap held in RAM, so it needs no partition and no change to the
  # LUKS layout. zstd gets ~3-4x on anonymous pages, meaning 50% of RAM as zram
  # buys substantially more than 50% back.
  #
  # This does NOT enable hibernation (that needs real disk swap >= RAM), but
  # hibernation was already impossible with an empty swapDevices. Ordinary
  # lid-close suspend is s2idle and unaffected by any of this.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  boot.kernel.sysctl = {
    # The stock 60 is tuned for swapping to a spinning disk. Swapping to zram
    # costs a memcpy and a zstd round-trip, not a seek, so the kernel should
    # reach for it eagerly instead of thrashing the page cache first. 180 is
    # the value the zram-generator upstream and Fedora both ship.
    "vm.swappiness" = 180;
  };

  # ------------------------------------------------------- build scheduling --
  # Nix defaults to max-jobs = <ncores> with cores = 0 (unlimited), i.e. up to
  # 16 derivations each free to spawn 16 compile threads. On a 28 W U-series
  # part that just buries the machine in context switches and pushes it into
  # thermal throttle, so the rebuild is not even faster. 4x4 keeps the total
  # at one thread per hardware thread.
  nix.settings = {
    max-jobs = 4;
    cores = 4;
  };

  # Even correctly sized, a rebuild should yield to whatever is on screen.
  # SCHED_BATCH costs builds very little (it only lengthens the effective
  # timeslice and skips wakeup preemption) while keeping the compositor and
  # editor from stuttering; idle I/O priority keeps the store writes off the
  # critical path of an interactive read.
  nix.daemonCPUSchedPolicy = "batch";
  nix.daemonIOSchedClass = "idle";
}
