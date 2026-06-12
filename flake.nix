{
  description = "rvo per-project NixOS dev VMs + portable home-manager config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, agenix, claude-code-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # Shared home-manager wiring used by every nixosConfiguration.
      hmModule = {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit claude-code-nix; };
        # users.<name>.imports is owned by each host file so GUI hosts can layer
        # gui.nix on top of common.nix without affecting headless hosts.
      };

      # mkHost: explicit host file — the right tool for one-offs (proj-api,
      # proj-web, future laptop/workstation) where the imports list is
      # custom.
      mkHost = hostFile:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit agenix claude-code-nix; };
          modules = [
            hostFile
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };

      # mkUniformHost: name -> nixosConfiguration. The right tool when you
      # have a fleet of dev VMs that share everything except their hardware
      # config and hostname. Hosts that need extra services (code-server,
      # etc.) should be written as one-offs via mkHost instead.
      mkUniformHost = name:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit agenix claude-code-nix; };
          modules = [
            ./hosts/hardware/${name}.nix
            ./modules/base.nix
            { networking.hostName = name; system.stateVersion = "26.05"; }
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            hmModule
          ];
        };

      # Populate when you have a uniform dev-VM fleet. Each name in this list
      # needs a matching hosts/hardware/<name>.nix file.
      uniformHosts = [ ];
    in
    {
      nixosConfigurations =
        (nixpkgs.lib.genAttrs uniformHosts mkUniformHost) // {
          proj-api = mkHost ./hosts/proj-api.nix;
          tepavi-dev = mkHost ./hosts/tepavi-dev.nix;
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
