{
  description = "rvo per-project NixOS dev VMs + portable home-manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # OpenClaw (AI agent gateway). Not in nixpkgs — this flake is the only
    # packaging, and it carries both the overlay (pkgs.openclaw) and the
    # home-manager module used by hosts/openclaw.nix.
    #
    # Upstream pins its own nixpkgs/home-manager and its templates tell you to
    # follow *theirs*. We follow ours instead, per this repo's convention: one
    # nixpkgs, one closure. Both track nixos-unstable, so the two are close —
    # but if an openclaw build ever breaks on an unstable bump, dropping these
    # two `follows` lines (letting upstream use its pinned inputs) is the first
    # thing to try.
    nix-openclaw = {
      url = "github:openclaw/nix-openclaw";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, home-manager, claude-code-nix, nix-openclaw, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Shared home-manager wiring used by every nixosConfiguration.
      # users.<name>.imports is owned by each host file so GUI hosts can layer
      # gui.nix on top of common.nix without affecting headless hosts.
      hmModule = {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit claude-code-nix nix-openclaw; };
      };

      mkHost = hostFile:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit claude-code-nix nix-openclaw; };
          modules = [
            hostFile
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };
    in
    {
      nixosConfigurations = {
        proj-api = mkHost ./hosts/proj-api.nix;
        tepavi-dev = mkHost ./hosts/tepavi-dev.nix;
        dev-desktop = mkHost ./hosts/dev-desktop.nix;
        laptop = mkHost ./hosts/laptop.nix;
        openclaw = mkHost ./hosts/openclaw.nix;
      };

      homeConfigurations.rvo = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit claude-code-nix; };
        modules = [
          ./home/common.nix
          {
            home.username = "rvo";
            home.homeDirectory = "/home/rvo";
            home.stateVersion = "26.05";
          }
        ];
      };
    };
}
