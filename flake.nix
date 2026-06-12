{
  description = "rvo per-project NixOS dev VMs + portable home-manager (fish) config";

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
  };

  outputs = { self, nixpkgs, home-manager, agenix, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      mkHost = hostFile:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit agenix; };
          modules = [
            hostFile
            agenix.nixosModules.default
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rvo = import ./home/fish.nix;
            }
          ];
        };
    in
    {
      nixosConfigurations = {
        proj-api = mkHost ./hosts/proj-api.nix;
        proj-web = mkHost ./hosts/proj-web.nix;
      };

      homeConfigurations.rvo = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          ./home/fish.nix
          {
            home.username = "rvo";
            home.homeDirectory = "/home/rvo";
            home.stateVersion = "26.05";
          }
        ];
      };
    };
}
