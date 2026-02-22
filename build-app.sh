#!/usr/bin/env bash
# Build Codigo and create a .app bundle so TCC can find Info.plist and show permission dialogs.
set -e
cd "$(dirname "$0")"

echo "Building Codigo..."
swift build

BIN_DIR=$(swift build --show-bin-path 2>/dev/null)
EXE="$BIN_DIR/Codigo"
OUTPUT="Codigo.app"
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"

if [[ ! -f "$EXE" ]]; then
  echo "Error: executable not found at $EXE" >&2
  exit 1
fi

echo "Creating $OUTPUT bundle..."
rm -rf "$OUTPUT"
mkdir -p "$MACOS"
cp "$EXE" "$MACOS/Codigo"
cp Package/Codigo.app/Contents/Info.plist "$CONTENTS/"

echo "Signing app (ad-hoc with entitlements for TCC)..."
codesign --force --deep -s - --entitlements Package/Codigo.app/Contents/Entitlements.plist "$OUTPUT"

# Remove quarantine so Gatekeeper doesn't block TCC (common when running from build dir)
xattr -cr "$OUTPUT" 2>/dev/null || true

echo "Done. Run with: open Codigo.app"
echo "Or: open -a Codigo.app"
