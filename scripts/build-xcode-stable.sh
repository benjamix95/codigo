#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT_DIR="${ROOT_DIR}/scripts"
source "${SCRIPT_DIR}/lib/solocode-validate-xcode.sh"
WORKSPACE="$ROOT_DIR/Solo Code.xcworkspace"
SCHEME="${1:-Solo Code}"
DESTINATION="${DESTINATION:-platform=macOS}"
CLONED_SOURCE_PACKAGES_DIR="${SOLOCODE_XCODE_CLONED_SOURCE_PACKAGES_DIR:-$ROOT_DIR/.xcode-spm-cache}"
PACKAGE_RESOLVE_STAMP="${SOLOCODE_XCODE_PACKAGE_RESOLVE_STAMP:-$(validation_cache_root "$ROOT_DIR")/build-xcode-stable-package-resolve.stamp}"
PACKAGE_CACHE_MARKER="${SOLOCODE_XCODE_PACKAGE_CACHE_MARKER:-$CLONED_SOURCE_PACKAGES_DIR/.solocode-build-xcode-stable-ready}"

mkdir -p "$CLONED_SOURCE_PACKAGES_DIR"

echo "[xcode-stable] workspace=$WORKSPACE"
echo "[xcode-stable] scheme=$SCHEME"
echo "[xcode-stable] clonedSourcePackagesDirPath=$CLONED_SOURCE_PACKAGES_DIR"

if should_resolve_packages "$ROOT_DIR"; then
  xcodebuild \
    -resolvePackageDependencies \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"
  mark_package_resolution_ready
else
  echo "[xcode-stable] package resolve skipped (cache warm)"
fi

xcodebuild \
  build \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_DIR"
