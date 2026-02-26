#!/usr/bin/env bash
# Build Codigo and create a .app bundle so TCC can find Info.plist and show permission dialogs.
set -e
cd "$(dirname "$0")"

echo "Building Codigo..."
swift build

BIN_DIR=$(swift build --show-bin-path 2>/dev/null)
EXE="$BIN_DIR/Codigo"

echo "Building bundled coderide-mcp-server..."
pushd CoderEngine >/dev/null
swift build --product coderide-mcp-server
MCP_BIN_DIR=$(swift build --show-bin-path 2>/dev/null)
MCP_EXE="$MCP_BIN_DIR/coderide-mcp-server"
popd >/dev/null

OUTPUT="Codigo.app"
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"
INFO_PLIST_SOURCE="Package/Codigo.app/Contents/Info.plist"
ENTITLEMENTS_SOURCE="Package/Codigo.app/Contents/Entitlements.plist"

if [[ ! -f "$INFO_PLIST_SOURCE" ]]; then
  INFO_PLIST_SOURCE="Sources/CoderIDE/Info.plist"
fi

if [[ ! -f "$EXE" ]]; then
  echo "Error: executable not found at $EXE" >&2
  exit 1
fi
if [[ ! -f "$MCP_EXE" ]]; then
  echo "Error: MCP server executable not found at $MCP_EXE" >&2
  exit 1
fi

echo "Creating $OUTPUT bundle..."
rm -rf "$OUTPUT"
mkdir -p "$MACOS"
cp "$EXE" "$MACOS/Codigo"
cp "$MCP_EXE" "$MACOS/coderide-mcp-server"
chmod +x "$MACOS/coderide-mcp-server"
cp "$INFO_PLIST_SOURCE" "$CONTENTS/Info.plist"

echo "Signing app (ad-hoc with entitlements for TCC)..."
if [[ -f "$ENTITLEMENTS_SOURCE" ]]; then
  codesign --force --deep -s - --entitlements "$ENTITLEMENTS_SOURCE" "$OUTPUT"
else
  codesign --force --deep -s - "$OUTPUT"
fi

# Remove quarantine so Gatekeeper doesn't block TCC (common when running from build dir)
xattr -cr "$OUTPUT" 2>/dev/null || true

echo "Done. Run with: open Codigo.app"
echo "Or: open -a Codigo.app"
