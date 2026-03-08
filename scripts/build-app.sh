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

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR/$APP_NAME"
cp -R "$DERIVED_DATA/Build/Products/Release/$APP_NAME" "$OUTPUT_DIR/$APP_NAME"
echo "Built: $OUTPUT_DIR/$APP_NAME"
