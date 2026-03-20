#!/bin/bash
set -euo pipefail

products_dir="${1:-${BUILT_PRODUCTS_DIR:-}}"

if [ -z "$products_dir" ] || [ ! -d "$products_dir" ]; then
  exit 0
fi

host_app_path="$(find "$products_dir" -maxdepth 1 -name '*.app' | head -n 1 || true)"
host_sign_identity=""

strip_xattrs() {
  target_path="$1"
  xattr -dr com.apple.provenance "$target_path" >/dev/null 2>&1 || true
  xattr -dr com.apple.quarantine "$target_path" >/dev/null 2>&1 || true
}

signature_is_valid() {
  target_path="$1"
  codesign --verify --strict "$target_path" >/dev/null 2>&1
}

signature_is_adhoc() {
  target_path="$1"
  codesign -dvv "$target_path" 2>&1 | grep -q '^Signature=adhoc$'
}

resolve_host_sign_identity() {
  if [ -z "$host_app_path" ] || [ ! -e "$host_app_path" ]; then
    return
  fi
  host_sign_identity="$(
    codesign -dvv "$host_app_path" 2>&1 |
      awk -F= '/^Authority=/{print $2; exit}'
  )"
}

resolve_sign_identity() {
  if [ -n "$host_sign_identity" ]; then
    printf '%s' "$host_sign_identity"
    return
  fi

  if [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    printf '%s' "$EXPANDED_CODE_SIGN_IDENTITY"
    return
  fi

  if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ "$CODE_SIGN_IDENTITY" != "Sign to Run Locally" ]; then
    printf '%s' "$CODE_SIGN_IDENTITY"
    return
  fi

  printf '%s' "-"
}

resign_path() {
  target_path="$1"
  if [ ! -e "$target_path" ]; then
    return
  fi
  if signature_is_valid "$target_path"; then
    if [ -n "$host_sign_identity" ] && signature_is_adhoc "$target_path"; then
      :
    else
      return
    fi
  fi
  sign_identity="$(resolve_sign_identity)"
  if [ -z "$sign_identity" ]; then
    return
  fi
  codesign \
    --force \
    --sign "$sign_identity" \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags \
    --generate-entitlement-der \
    "$target_path" >/dev/null
}

bootstrap_bundle() {
  bundle_path="$1"
  strip_xattrs "$bundle_path"

  if [ -d "$bundle_path/Contents/Frameworks" ]; then
    while IFS= read -r -d '' framework_path; do
      strip_xattrs "$framework_path"
      resign_path "$framework_path"
    done < <(find "$bundle_path/Contents/Frameworks" -mindepth 1 -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0)
  fi

  if [ -d "$bundle_path/Contents/PlugIns" ]; then
    while IFS= read -r -d '' nested_bundle; do
      strip_xattrs "$nested_bundle"
      bootstrap_bundle "$nested_bundle"
    done < <(find "$bundle_path/Contents/PlugIns" -mindepth 1 -maxdepth 1 -name '*.xctest' -print0)
  fi

  binary_name="$(basename "$bundle_path" .xctest)"
  binary_path="$bundle_path/Contents/MacOS/$binary_name"
  if [ -f "$binary_path" ]; then
    strip_xattrs "$binary_path"
    resign_path "$binary_path"
  fi

  resign_path "$bundle_path"
}

resign_host_app_if_needed() {
  if [ -z "$host_app_path" ] || [ ! -e "$host_app_path" ]; then
    return
  fi
  if [ -z "$host_sign_identity" ]; then
    return
  fi
  strip_xattrs "$host_app_path"
  codesign \
    --force \
    --deep \
    --sign "$host_sign_identity" \
    --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags \
    --generate-entitlement-der \
    "$host_app_path" >/dev/null
}

resolve_host_sign_identity

while IFS= read -r -d '' bundle_path; do
  bootstrap_bundle "$bundle_path"
done < <(find "$products_dir" -name '*.xctest' -print0)

resign_host_app_if_needed
