{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,
  copyDesktopItems,
  wrapGAppsHook3,
  alsa-lib,
  bash,
  cairo,
  coreutils,
  dbus,
  fontconfig,
  freetype,
  gdk-pixbuf,
  getent,
  glib,
  gtk3,
  hunspell,
  iproute2,
  libayatana-appindicator,
  libgbm,
  libglvnd,
  libx11,
  libxcursor,
  libxext,
  libxi,
  libxinerama,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxtst,
  nftables,
  pango,
  systemd,
  wayland,
  xdg-utils,
  zlib,
}:
let
  source = builtins.fromJSON (builtins.readFile ./sources.json);
  # Some libraries live inside the GraalVM images and are extracted at runtime.
  # autoPatchelf cannot see them, so expose their dependencies explicitly.
  nativeLibraries = [
    stdenv.cc.cc.lib
    stdenv.cc.libc
    alsa-lib
    cairo
    dbus
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk3
    hunspell
    libayatana-appindicator
    libgbm
    libglvnd
    libx11
    libxcursor
    libxext
    libxi
    libxinerama
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxtst
    pango
    systemd
    wayland
    zlib
  ];
  libraryPath = lib.makeLibraryPath nativeLibraries;
  commandPath = lib.makeBinPath [
    bash
    coreutils
    getent
    glib
    iproute2
    nftables
    systemd
    xdg-utils
  ];
in
stdenv.mkDerivation (finalAttrs: {
  pname = "wgtunnel";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url sha256;
  };

  strictDeps = true;
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    copyDesktopItems
    wrapGAppsHook3
  ];
  buildInputs = nativeLibraries;
  dontBuild = true;
  dontConfigure = true;
  dontStrip = true;
  # Wrap only the GUI, not the bundled ELF libraries or the headless daemon.
  dontWrapGApps = true;
  # Run autoPatchelf explicitly before installing the GUI's inherited RPATH.
  dontAutoPatchelf = true;

  desktopItems = [
    (makeDesktopItem {
      name = "wgtunnel";
      desktopName = "WG Tunnel";
      comment = "WireGuard and AmneziaWG VPN client";
      exec = "wgtunnel";
      icon = "wgtunnel";
      categories = [ "Network" ];
      startupWMClass = "wgtunnel";
      terminal = false;
    })
  ];

  installPhase = ''
    runHook preInstall

    app="$out/libexec/wgtunnel"
    mkdir -p "$app" "$out/bin"
    # Keep the executable, sidecars, and native libraries in their original
    # relative locations. Never run upstream's imperative /opt installer.
    cp -a ./. "$app/"
    chmod -R u+w "$app"
    rm "$app/install.sh" "$app/uninstall.sh" "$app/wgtunnel-daemon.service"

    install -Dm644 ${./assets/wgtunnel.png} "$out/share/icons/hicolor/512x512/apps/wgtunnel.png"
    install -Dm644 ${./assets/UPSTREAM-LICENSE} "$out/share/licenses/wgtunnel/LICENSE"
    runHook postInstall
  '';

  preFixup = ''
    addAutoPatchelfSearchPath "$out/libexec/wgtunnel"
    addAutoPatchelfSearchPath "$out/libexec/wgtunnel/lib"
  '';

  postFixup = ''
    app="$out/libexec/wgtunnel"
    autoPatchelf "$app"
    # RPATH (rather than RUNPATH) also applies to dependencies of the JNI
    # libraries extracted by GraalVM. Keep it on the native GUI itself so
    # upstream's autostart/relaunch code can also launch that executable.
    patchelf --force-rpath --set-rpath "$app:$app/lib:${libraryPath}" "$app/wgtunnel"

    makeWrapper "$app/wgtunnel" "$out/bin/wgtunnel" \
      "''${gappsWrapperArgs[@]}" \
      --set WGTUNNEL_VARIANT release \
      --prefix LD_LIBRARY_PATH : "$app:$app/lib:${libraryPath}" \
      --prefix PATH : ${lib.escapeShellArg commandPath}

    makeWrapper "$app/bin/wgtunnel-daemon" "$out/bin/wgtunnel-daemon" \
      --set WG_TUNNEL_SERVICE 1 \
      --set WGTUNNEL_VARIANT release \
      --prefix LD_LIBRARY_PATH : ${lib.escapeShellArg (lib.makeLibraryPath [ stdenv.cc.libc zlib ])} \
      --prefix PATH : ${lib.escapeShellArg commandPath}
  '';

  meta = {
    description = "Desktop WireGuard and AmneziaWG client with a system daemon";
    homepage = "https://github.com/wgtunnel/desktop";
    changelog = "https://github.com/wgtunnel/desktop/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "wgtunnel";
  };
})
