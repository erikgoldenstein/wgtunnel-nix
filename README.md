# WG Tunnel for NixOS

Nix packaging and a NixOS module for [WG Tunnel Desktop](https://github.com/wgtunnel/desktop).
Packages upstream **2.4.0** for **x86_64-linux**, including its native GUI and
privileged system daemon. The release URL and SHA-256 are pinned in
[`sources.json`](sources.json); the standalone flake pins NixOS 26.05.

This repackages the upstream binaries. It does not rebuild the application from
source. The original installer is never executed. Files live in the Nix store;
NixOS manages the daemon and its writable directories.

The GUI and daemon have been manually tested on NixOS through `nix shell`.
The declarative NixOS module has not yet been verified through system activation.

## Install on NixOS

Add this input to your system flake:

```nix
wgtunnel-nix = {
  url = "github:erikgoldenstein/wgtunnel-nix";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Import the module in your NixOS configuration and enable it:

```nix
{ inputs, ... }:
{
  imports = [ inputs.wgtunnel-nix.nixosModules.default ];
  services.wgtunnel = {
    enable = true;
    autostart = true; # Optional; the default is false.
  };
}
```

Pass `inputs` through your existing `specialArgs` if using
[`examples/configuration.nix`](examples/configuration.nix), or refer to the
module directly in your flake's `nixosSystem.modules` list. An additional
flake-parts example for `nixie` is in [`examples/nixie.nix`](examples/nixie.nix).

Rebuild your system as usual. Launch **WG Tunnel** from the application menu or
run `wgtunnel` as your normal user. After the first switch, log out and back in
so the keyring login integration and graphical session service take effect.

Without flakes, import `./module.nix` and set `services.wgtunnel.enable = true`.
To obtain only the package with an existing package set:

```nix
pkgs.callPackage /path/to/wgtunnel-nix/package.nix { }
```

The flake also exports `packages.x86_64-linux.default`,
`packages.x86_64-linux.wgtunnel`, `apps.x86_64-linux.default`, and
`overlays.default`. Running the GUI alone does not install or start the daemon;
use the NixOS module to get a functioning system installation.

## Integration details

- The `wgtunnel-daemon` system service starts at boot with upstream's early
  ordering and capabilities. Authentication uses upstream's per-user IPC keys;
  no additional user group or passwordless sudo rule is added.
- The module selects the nftables backend by default. It rejects
  `networking.nftables.flushRuleset = true`, which would erase the VPN's tables
  on firewall reload. Reverse path filtering defaults to `loose` for policy
  routing. It does not disable the NixOS firewall or open listening ports.
- systemd-resolved handles tunnel DNS through D-Bus. NetworkManager is set to
  use resolved when enabled. This avoids the daemon's fallback of writing
  `/etc/resolv.conf`, which is unsuitable when it points into the Nix store.
- GNOME Keyring supplies the Secret Service used for the GUI's database
  encryption key. Greetd picks up NixOS's keyring PAM integration automatically.
- Visible native libraries are patched for Nix. Runtime library paths also
  cover libraries embedded inside the GraalVM images. GTK settings and graphics
  dependencies are included without changing the desktop's selected theme.
- The tarball's upstream self-updater is unsupported; update through this
  package. Keep upstream's login autostart option off when using the module's
  `autostart` option to avoid duplicate launches.

### Options

| Option | Default | Purpose |
| --- | --- | --- |
| `services.wgtunnel.enable` | `false` | Install the client and enable the daemon |
| `services.wgtunnel.package` | This package | Override the package |
| `services.wgtunnel.autostart` | `false` | Start the GUI with the graphical session |
| `services.wgtunnel.useResolved` | `true` | Configure resolved and NetworkManager DNS |
| `services.wgtunnel.enableGnomeKeyring` | `true` | Enable the Secret Service provider |

If KWallet or KeePassXC already provides Secret Service, set
`services.wgtunnel.enableGnomeKeyring = false`. If you set `useResolved = false`,
provide a working DNS setup yourself; the fallback requires a writable resolver
file. GUI autostart follows `graphical-session.target`; Sway must start that
target, as Home Manager's Sway systemd integration does.

### Data and logs

| Location | Contents |
| --- | --- |
| `~/.local/share/wgtunnel` (or `$XDG_DATA_HOME/wgtunnel`) | GUI database and logs |
| `~/.cache/wgtunnel` (or `$XDG_CACHE_HOME/wgtunnel`) | GUI cache |
| `/var/lib/wgtunnel` | Daemon state, logs and restoration data |
| `/run/wgtunnel/daemon.sock` | GUI/daemon socket |
| `$XDG_RUNTIME_DIR/wgtunnel/ipc.key` | Current user's private IPC key |
| OS keyring, service `wg_tunnel` | GUI database encryption key |

Disabling the module leaves saved data and keyring entries intact.

For a connection or startup failure, inspect:

```sh
systemctl status wgtunnel-daemon
journalctl -u wgtunnel-daemon -b
systemctl --user status wgtunnel
journalctl --user -u wgtunnel -b
```

## Try it without installing

Use two terminals. Leave the privileged daemon running in the first:

```sh
nix shell github:erikgoldenstein/wgtunnel-nix --command bash -c 'sudo "$(command -v wgtunnel-daemon)"'
```

Launch the GUI as your normal user in the second:

```sh
nix shell github:erikgoldenstein/wgtunnel-nix --command wgtunnel
```

Stop the foreground daemon with Ctrl+C before switching to the NixOS service.
These commands do not configure the host's DNS, firewall or keyring; use the
NixOS module for a persistent installation.

## Build the package separately

```sh
git clone https://github.com/erikgoldenstein/wgtunnel-nix.git
cd wgtunnel-nix
nix build path:.
```

The `.upstream/` directory is a download/inspection cache and is not a build
dependency. A `path:` flake can copy that cache into the Nix store along with
the project. Remove the cache when finished inspecting upstream, or use a Git
checkout with the project files tracked and `.upstream/` ignored to avoid that
copy. Retain `sources.json` and the files in `assets/`.

To reuse the downloaded archive without downloading it again, import it into
the host's store before building:

```sh
nix-store --add-fixed sha256 .upstream/2.4.0/wgtunnel-2.4.0-linux-x64.tar.gz
```

## Updating the pin

```sh
nix shell nixpkgs#curl nixpkgs#jq --command bash scripts/fetch-upstream.sh 2.4.0
```

Replace the final argument with the desired stable version. The script downloads
release metadata, the Linux x64 tarball, and source for inspection under
`.upstream/<version>/`. It verifies GitHub's asset digest when available and
records the archive's SHA-256, version and URL in `sources.json`. It does not
install anything or start services.

For a new version, review changes to the archive layout, native dependencies
and upstream daemon unit before rebuilding. The GUI and daemon are updated
together from the same release archive. Update the vendored icon and upstream
license if those change. Refresh a consuming flake's `wgtunnel-nix` input lock
after changing this directory.

## License

The packaging is MIT licensed. The vendored icon is from upstream under its MIT
license, included in [`assets/UPSTREAM-LICENSE`](assets/UPSTREAM-LICENSE).
Bundled dependencies retain their upstream licenses.
