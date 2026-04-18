#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_DIR="$ROOT_DIR/.submax/bin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ASSET_MATCH="darwin-arm64" ;;
  x86_64) ASSET_MATCH="darwin-amd64" ;;
  *)
    echo "unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

DOWNLOAD_URL="$(python3 - <<'PY'
import json
import platform
import urllib.request

arch = platform.machine()
match = "darwin-arm64" if arch == "arm64" else "darwin-amd64"
with urllib.request.urlopen("https://api.github.com/repos/SagerNet/sing-box/releases/latest", timeout=30) as resp:
    release = json.load(resp)
for asset in release.get("assets", []):
    name = asset.get("name", "")
    if match in name and name.endswith(".tar.gz"):
        print(asset["browser_download_url"])
        break
else:
    raise SystemExit(f"no sing-box asset found for {match}")
PY
)"

mkdir -p "$INSTALL_DIR"
curl -L "$DOWNLOAD_URL" -o "$TMP_DIR/sing-box.tar.gz"
tar -xzf "$TMP_DIR/sing-box.tar.gz" -C "$TMP_DIR"
FOUND="$(find "$TMP_DIR" -type f -name sing-box | head -n 1)"
cp "$FOUND" "$INSTALL_DIR/sing-box"
chmod +x "$INSTALL_DIR/sing-box"
"$INSTALL_DIR/sing-box" version
