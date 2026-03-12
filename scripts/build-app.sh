#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$REPO_ROOT/.xcodebuild}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/dist}"
APP_NAME="Solo Code.app"

xcodebuild \
  -workspace "$REPO_ROOT/Solo Code.xcworkspace" \
  -scheme "Solo Code-Release" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
CONFIGURATION=Release \
SOLOCODE_MCP_SERVER_BUNDLE_DIR="$APP_PATH/Contents/MacOS" \
  "$REPO_ROOT/scripts/build_rust_mcp_server.sh"
CONFIGURATION=Release \
SOLOCODE_MCP_SERVER_BUNDLE_DIR="$APP_PATH/Contents/MacOS" \
  "$REPO_ROOT/scripts/build_rust_mcp_lifecycle_backend.sh"
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP_PATH"
"$REPO_ROOT/scripts/validate_app_bundle.sh" "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$APP_NAME"
cp -R "$APP_PATH" "$OUTPUT_DIR/$APP_NAME"
echo "Built: $OUTPUT_DIR/$APP_NAME"
