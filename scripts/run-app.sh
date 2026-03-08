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

open -na "$DERIVED_DATA/Build/Products/Debug/Solo Code.app"
