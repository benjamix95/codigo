#!/bin/sh
set -eu

products_dir="${1:-${BUILT_PRODUCTS_DIR:-}}"

if [ -z "$products_dir" ] || [ ! -d "$products_dir" ]; then
  exit 0
fi

strip_xattrs() {
  target_path="$1"
  xattr -dr com.apple.provenance "$target_path" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "$target_path" >/dev/null 2>&1 || true
}

resign_path() {
  target_path="$1"
  if [ ! -e "$target_path" ]; then
    return
  fi
  codesign \
    --force \
    --sign - \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags \
    --generate-entitlement-der \
    "$target_path" >/dev/null
}

bootstrap_bundle() {
  bundle_path="$1"
  strip_xattrs "$bundle_path"

  if [ -d "$bundle_path/Contents/Frameworks" ]; then
    find "$bundle_path/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) | while IFS= read -r framework_path; do
      strip_xattrs "$framework_path"
      resign_path "$framework_path"
    done
  fi

  if [ -d "$bundle_path/Contents/PlugIns" ]; then
    find "$bundle_path/Contents/PlugIns" -mindepth 1 -maxdepth 1 -name '*.xctest' | while IFS= read -r nested_bundle; do
      strip_xattrs "$nested_bundle"
      resign_path "$nested_bundle"
    done
  fi

  binary_name="$(basename "$bundle_path" .xctest)"
  binary_path="$bundle_path/Contents/MacOS/$binary_name"
  if [ -f "$binary_path" ]; then
    strip_xattrs "$binary_path"
    resign_path "$binary_path"
  fi

  resign_path "$bundle_path"
}

find "$products_dir" -name '*.xctest' | while IFS= read -r bundle_path; do
  bootstrap_bundle "$bundle_path"
done
