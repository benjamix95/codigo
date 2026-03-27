#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKSPACE="$ROOT_DIR/Solo Code.xcworkspace"
SCHEME="${1:-Solo Code}"
DESTINATION="${DESTINATION:-platform=macOS}"
CLONED_SOURCE_PACKAGES_DIR="${SOLOCODE_XCODE_CLONED_SOURCE_PACKAGES_DIR:-$ROOT_DIR/.xcode-spm-cache}"

mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"

echo "[xcode-stable] workspace=$WORKSPACE"
echo "[xcode-stable] scheme=$SCHEME"
echo "[xcode-stable] clonedSourcePackagesDirPath=$CLONED_SOURCE_PACKAGES_DIR"

xcodebuild \
  -resolvePackageDependencies \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"

xcodebuild \
  build \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"
