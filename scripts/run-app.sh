#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/.xcodebuild"

xcodebuild \
  -workspace "$REPO_ROOT/Solo Code.xcworkspace" \
  -scheme "Solo Code-Debug" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug/Solo Code.app"
CONFIGURATION=Debug \
SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR="$APP_PATH/Contents/MacOS/solocode_rust" \
  "$REPO_ROOT/scripts/build_rust_search_backend.sh"
CONFIGURATION=Debug \
SOLOCODE_MCP_SERVER_BUNDLE_DIR="$APP_PATH/Contents/MacOS" \
  "$REPO_ROOT/scripts/build_rust_mcp_server.sh"
CONFIGURATION=Debug \
SOLOCODE_MCP_SERVER_BUNDLE_DIR="$APP_PATH/Contents/MacOS" \
  "$REPO_ROOT/scripts/build_rust_mcp_lifecycle_backend.sh"
codesign --force --deep --sign - "$APP_PATH"
"$REPO_ROOT/scripts/validate_app_bundle.sh" "$APP_PATH"

open -na "$APP_PATH"
