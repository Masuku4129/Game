#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSET_DIR="$ROOT/assets/reference_anim"
ZIP="$ASSET_DIR/vinish_character_animations.zip"
mkdir -p "$ASSET_DIR"

URL="https://models.vinish.dev/animations/animations.zip"
echo "Downloading free rigged female/male character animation pack (CC BY 4.0)..."
if ! curl -fL --retry 3 --connect-timeout 20 "$URL" -o "$ZIP"; then
  echo "Download failed: network/source unavailable. No account or API is required."
  exit 2
fi
if ! unzip -t "$ZIP" >/dev/null; then
  echo "Downloaded file is not a valid ZIP. Removing it."
  rm -f "$ZIP"
  exit 3
fi
unzip -o "$ZIP" -d "$ASSET_DIR"
echo "Archive extracted to: $ASSET_DIR"
echo "Inspect model/clip names before importing. Attribution required: vinish.dev, CC BY 4.0."
