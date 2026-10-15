{ config, lib, pkgs, ... }:
let
  cfg = config.services.wgtunnel;
  capabilities = [
    "CAP_NET_ADMIN"
    "CAP_NET_BIND_SERVICE"
    "CAP_NET_RAW"
    "CAP_DAC_OVERRIDE"
  ];
in
{
  options.services.wgtunnel = {
    enable = lib.mkEnableOption "WG Tunnel desktop client and system daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "WG Tunnel package providing the GUI and daemon.";
    };

    useResolved = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable systemd-resolved and configure NetworkManager to use it.
        The daemon configures tunnel DNS through resolved's D-Bus interface.
        Disable this only when supplying your own compatible DNS setup;
        upstream's fallback needs a writable /etc/resolv.conf.
      '';
    };

    enableGnomeKeyring = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable GNOME Keyring to store the GUI's database encryption key.
        Disable when your desktop already provides another Secret Service,
        such as KWallet or KeePassXC.
      '';
    };

    autostart = lib.mkEnableOption "starting the WG Tunnel GUI with the graphical session";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
        message = "This WG Tunnel package currently supports x86_64-linux only.";
      }
      {
        assertion = config.networking.nftables.enable;
        message = "WG Tunnel requires the nftables firewall backend; enable networking.nftables.enable.";
      }
      {
        assertion = !config.networking.nftables.flushRuleset;
        message = "WG Tunnel manages its own nftables tables. Set networking.nftables.flushRuleset = false so firewall reloads preserve them.";
      }
      {
        assertion = !cfg.useResolved || config.services.resolved.enable;
        message = "services.wgtunnel.useResolved requires services.resolved.enable.";
      }
    ];

    environment.systemPackages = [ cfg.package ];
    networking.nftables.enable = lib.mkDefault true;
    # Full tunnel policy routing can fail strict reverse path filtering.
    networking.firewall.checkReversePath = lib.mkDefault "loose";
    boot.kernelModules = [ "tun" ];

    services.resolved.enable = lib.mkIf cfg.useResolved (lib.mkDefault true);
    networking.networkmanager.dns =
      lib.mkIf (cfg.useResolved && config.networking.networkmanager.enable)
        (lib.mkDefault "systemd-resolved");
    services.gnome.gnome-keyring.enable =
      lib.mkIf cfg.enableGnomeKeyring (lib.mkDefault true);

    # Keep upstream's early startup ordering for kill switch restoration.
    # Do not wait for network-online.target: that would defeat early restore.
    systemd.services.wgtunnel-daemon = {
      description = "WG Tunnel Daemon";
      documentation = [ "https://wgtunnel.com" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "network.target" "network-pre.target" ];
      wants = [ "network.target" ];
      after = [ "local-fs.target" ];
      unitConfig = {
        StartLimitBurst = 5;
        StartLimitIntervalSec = 20;
      };
      environment = {
        WG_TUNNEL_SERVICE = "1";
        WGTUNNEL_VARIANT = "release";
        HOME = "/var/lib/wgtunnel";
      };
      serviceConfig = {
        Type = "exec";
        ExecStart = "${cfg.package}/bin/wgtunnel-daemon";
        WorkingDirectory = "/var/lib/wgtunnel";
        User = "root";
        Group = "root";
        Restart = "always";
        RestartSec = "1s";
        StandardOutput = "journal";
        StandardError = "journal";
        # Upstream manages permissions on sockets and private data explicitly.
        UMask = "0000";
        ProtectSystem = true;
        StateDirectory = "wgtunnel";
        StateDirectoryMode = "0700";
        LogsDirectory = "wgtunnel";
        ConfigurationDirectory = "wgtunnel";
        RuntimeDirectory = "wgtunnel";
        RuntimeDirectoryMode = "0755";
        RuntimeDirectoryPreserve = "restart";
        CapabilityBoundingSet = capabilities;
        AmbientCapabilities = capabilities;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_NETLINK" "AF_UNIX" ];
        KillSignal = "SIGTERM";
        TimeoutStopSec = 30;
        # Authentication checks keys in /run/user/<uid>/wgtunnel/ipc.key,
        # or in the user's home on systems without a runtime directory.
        # Do not use ProtectHome or PrivateUsers here.
      };
    };

    systemd.user.services.wgtunnel = lib.mkIf cfg.autostart {
      description = "WG Tunnel desktop client";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${cfg.package}/bin/wgtunnel";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
  };
}
