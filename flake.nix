{
  description = "rvo per-project NixOS dev VMs + portable home-manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, claude-code-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Shared home-manager wiring used by every nixosConfiguration.
      # users.<name>.imports is owned by each host file so GUI hosts can layer
      # gui.nix on top of common.nix without affecting headless hosts.
      hmModule = {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit claude-code-nix; };
      };

      mkHost = hostFile:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit claude-code-nix; };
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
