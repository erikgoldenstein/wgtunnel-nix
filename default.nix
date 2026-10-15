# Also usable without flakes: pkgs.callPackage /path/to/wgtunnel-nix { }
{ pkgs ? import <nixpkgs> { } }:
pkgs.callPackage ./package.nix { }
