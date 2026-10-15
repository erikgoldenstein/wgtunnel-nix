{
  description = "WG Tunnel desktop client and daemon for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system} = rec {
        wgtunnel = pkgs.callPackage ./package.nix { };
        default = wgtunnel;
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.wgtunnel}/bin/wgtunnel";
        meta.description = "WG Tunnel desktop client";
      };

      overlays.default = final: prev: {
        wgtunnel = final.callPackage ./package.nix { };
      };

      nixosModules = rec {
        wgtunnel = import ./module.nix;
        default = wgtunnel;
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
