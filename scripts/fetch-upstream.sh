#!/usr/bin/env bash
# Download inputs only. Does not install or execute WG Tunnel.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:-2.4.0}
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo 'Expected a version such as 2.4.0' >&2
  exit 1
fi
for tool in curl jq sha256sum tar; do
  command -v "$tool" >/dev/null || { echo "Missing command: $tool" >&2; exit 1; }
done
cache="$root/.upstream/$version"
mkdir -p "$cache"
curl --fail --location --retry 3 \
  "https://api.github.com/repos/wgtunnel/desktop/releases/tags/v$version" \
  --output "$cache/release.json.tmp"
mv "$cache/release.json.tmp" "$cache/release.json"
asset=$(jq -er '[.assets[] | select(.name | test("linux.*(x64|amd64).*\\.tar\\.gz$"; "i"))] | if length == 1 then .[0] else error("Expected one Linux x64 tarball") end' "$cache/release.json")
name=$(jq -r .name <<< "$asset")
url=$(jq -r .browser_download_url <<< "$asset")
curl --fail --location --retry 3 "$url" --output "$cache/$name.tmp"
digest=$(jq -r '.digest // empty' <<< "$asset")
if [[ $digest == sha256:* ]]; then
  printf '%s  %s\n' "${digest#sha256:}" "$cache/$name.tmp" | sha256sum --check
fi
mv "$cache/$name.tmp" "$cache/$name"
curl --fail --location --retry 3 \
  "https://api.github.com/repos/wgtunnel/desktop/tarball/v$version" \
  --output "$cache/source.tar.gz.tmp"
mv "$cache/source.tar.gz.tmp" "$cache/source.tar.gz"
mkdir -p "$cache/source" "$cache/release"
tar -xzf "$cache/source.tar.gz" -C "$cache/source" --strip-components=1 --no-same-owner
tar -xzf "$cache/$name" -C "$cache/release" --no-same-owner
hash=$(sha256sum "$cache/$name")
hash=${hash%% *}
jq -n --arg version "$version" --arg url "$url" --arg sha256 "$hash" \
  '{version: $version, url: $url, sha256: $sha256}' > "$root/sources.json"
printf '\nDownloaded upstream %s into %s\nPinned release in %s/sources.json\n' "$version" "$cache" "$root"
