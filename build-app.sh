#!/usr/bin/env bash
# Build Codigo and create a .app bundle so TCC can find Info.plist and show permission dialogs.
set -e
cd "$(dirname "$0")"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-auto}"
SIGN_TIMEOUT_OPT="--timestamp"
NOTARIZE="${NOTARIZE:-false}"

is_truthy() {
  case "$1" in
    1|true|TRUE|True|yes|YES|Yes|on|ON|On|y|Y)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_signing_identity() {
  if [[ "$SIGN_IDENTITY" == "-" || "$SIGN_IDENTITY" == "adhoc" || "$SIGN_IDENTITY" == "auto-adhoc" ]]; then
    echo "-"
    return
  fi

  if [[ "$SIGN_IDENTITY" == "auto" || -z "$SIGN_IDENTITY" ]]; then
    local auto_identity
    auto_identity="$(security find-identity -v -p codesigning | awk '/Developer ID Application:/{print $2; exit}')"
    if [[ -n "$auto_identity" ]]; then
      echo "$auto_identity"
    else
      echo "-"
    fi
    return
  fi

  echo "$SIGN_IDENTITY"
}

effective_sign_identity="$(resolve_signing_identity)"
is_notary_enabled=false
if is_truthy "$NOTARIZE"; then
  is_notary_enabled=true
fi

notarytool_auth_args=()
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  if [[ ! -f "$NOTARY_KEY_PATH" ]]; then
    echo "Notarytool key file not found at $NOTARY_KEY_PATH"
    exit 1
  fi
  notarytool_auth_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_APP_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
  notarytool_auth_args=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_APP_PASSWORD" --team-id "$NOTARY_TEAM_ID")
fi

notary_is_configured=false
if (( ${#notarytool_auth_args[@]} > 0 )); then
  notary_is_configured=true
fi

run_notarization() {
  local target_path="$1"
  if [[ "$is_notary_enabled" != "true" ]]; then
    echo "Skipping notarization (NOTARIZE=$NOTARIZE)."
    return 0
  fi

  if [[ "$target_path" != *.app ]]; then
    echo "Skipping notarization: expected .app bundle at $target_path"
    return 0
  fi

  if [[ "$effective_sign_identity" == "-" ]]; then
    echo "Notarytool requires a real signing identity. Skipping because signing is ad-hoc."
    return 1
  fi

  if [[ "$notary_is_configured" != "true" ]]; then
    echo "Notarization requested but credentials not configured. Set either:"
    echo "  API key mode: NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID"
    echo "  Apple ID mode: NOTARY_APPLE_ID + NOTARY_APP_PASSWORD + NOTARY_TEAM_ID"
    return 1
  fi

  echo "Submitting for notarization..."
  local notary_log
  notary_log="/tmp/codigo-notary-${RANDOM}-$(date +%s).log"
  if ! xcrun notarytool submit "$target_path" --wait --output-format json \
    "${notarytool_auth_args[@]}" >"$notary_log" 2>&1; then
    echo "Notarytool submission failed. See: $notary_log"
    sed -n '1,120p' "$notary_log"
    return 1
  fi

  echo "Notarization complete. Log: $notary_log"
  echo "Stapling ticket..."
  xcrun stapler staple "$target_path"
  echo "Stapling done."
  return 0
}

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

echo "Signing app with: $effective_sign_identity"
if [[ "$effective_sign_identity" == "-" ]]; then
  echo "Signing app ad-hoc (no Developer ID identity available)."
  if [[ -f "$ENTITLEMENTS_SOURCE" ]]; then
    codesign --force --deep -s - --entitlements "$ENTITLEMENTS_SOURCE" "$OUTPUT"
  else
    codesign --force --deep -s - "$OUTPUT"
  fi
else
  SIGN_ARGS=(--force --deep --options runtime "$SIGN_TIMEOUT_OPT")
  if [[ -f "$ENTITLEMENTS_SOURCE" ]]; then
    SIGN_ARGS+=(--entitlements "$ENTITLEMENTS_SOURCE")
  fi
  SIGN_ARGS+=(-s "$effective_sign_identity" "$OUTPUT")
  codesign "${SIGN_ARGS[@]}"
fi

# Remove quarantine so Gatekeeper doesn't block TCC (common when running from build dir)
xattr -cr "$OUTPUT" 2>/dev/null || true

echo "Verifying signing..."
codesign --verify --strict --deep --verbose=2 "$OUTPUT"
if spctl --assess --type execute --verbose=1 "$OUTPUT" >/dev/null 2>&1; then
  echo "Gatekeeper validation: OK"
else
  echo "Gatekeeper validation: pending or blocked in this environment (expected on ad-hoc / non-notarized builds)."
fi

if ! run_notarization "$OUTPUT"; then
  if [[ "$is_notary_enabled" == "true" ]]; then
    echo "Build completed, but notarization failed."
    exit 1
  fi
fi

echo "Done. Run with: open Codigo.app"
echo "Or: open -a Codigo.app"
