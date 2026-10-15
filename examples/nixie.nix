# With the wgtunnel-nix input from README.md, copy this file to
# nixie/modules/programs/desktop/wgtunnel.nix. import-tree picks it up.
{ inputs, ... }:
let
  desktop = {
    imports = [ inputs.wgtunnel-nix.nixosModules.default ];
    services.wgtunnel = {
      enable = true;
      autostart = true;
    };
  };
in
{
  flake.modules.nixos.cutiepad = desktop;
  flake.modules.nixos.cutiepad-nosec = desktop;
}
