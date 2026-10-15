{ inputs, ... }:
{
  imports = [ inputs.wgtunnel-nix.nixosModules.default ];
  services.wgtunnel.enable = true;
  # Optional: otherwise launch wgtunnel from your application menu.
  services.wgtunnel.autostart = true;
}
