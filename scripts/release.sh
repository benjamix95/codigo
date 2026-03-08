#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$REPO_ROOT/App/SoloCodeApp/Sources/Info.plist"
MANIFEST_FILE="$REPO_ROOT/docs/update/manifest.json"
RELEASE_NOTES_DIR="$REPO_ROOT/docs/release-notes"
VERSION=""
BUILD="1"
DOWNLOAD_URL="https://github.com/benjamix95/codigo/releases/download/v{VERSION}/Codigo.app.zip"
NOTES_FILE=""
CHECK_ONLY="false"
NOTARIZE="false"
CODESIGN_IDENTITY=""
NOTARY_KEY_PATH=""
NOTARY_KEY_ID=""
NOTARY_ISSUER_ID=""
NOTARY_APPLE_ID=""
NOTARY_APP_PASSWORD=""
NOTARY_TEAM_ID=""

usage() {
  cat <<EOF
Usage: $0 --version <versione> [--build <build>] [--download-url <url>] [--notes-file <path>] [--check-only]
      [--notarize] [--codesign-identity <string>]

Notarization:
  --notarize
  --notary-key-path <file>
  --notary-key-id <id>
  --notary-issuer-id <id>
  --notary-apple-id <email>
  --notary-password <password-or-keychain-ref>
  --notary-team-id <team-id>

Example:
  $0 --version 1.0.1 --build 2 --download-url https://github.com/benjamix95/codigo/releases/download/v1.0.1/Codigo.app.zip
  $0 --version 1.0.1 --build 2 --download-url https://github.com/benjamix95/codigo/releases/download/v1.0.1/Codigo.app.zip --notarize --notary-key-path /path/AuthKey.p8 --notary-key-id XYZ123ABC --notary-issuer-id 00000000-1111-2222-3333-444444444444 --codesign-identity "Developer ID Application: NOME (TEAMID)"
EOF
}

escape_json() {
  local input="$1"
  local escaped="$input"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\r'/}"
  escaped="${escaped//$'\n'/\\\\n}"
  printf '%s' "$escaped"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD="$2"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    --notes-file)
      NOTES_FILE="$2"
      shift 2
      ;;
    --check-only)
      CHECK_ONLY="true"
      shift
      ;;
    --notarize)
      NOTARIZE="true"
      shift
      ;;
    --codesign-identity)
      CODESIGN_IDENTITY="$2"
      shift 2
      ;;
    --notary-key-path)
      NOTARY_KEY_PATH="$2"
      shift 2
      ;;
    --notary-key-id)
      NOTARY_KEY_ID="$2"
      shift 2
      ;;
    --notary-issuer-id)
      NOTARY_ISSUER_ID="$2"
      shift 2
      ;;
    --notary-apple-id)
      NOTARY_APPLE_ID="$2"
      shift 2
      ;;
    --notary-password)
      NOTARY_APP_PASSWORD="$2"
      shift 2
      ;;
    --notary-team-id)
      NOTARY_TEAM_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "Missing required --version argument."
  usage
  exit 1
fi

if [[ "$NOTES_FILE" == "" ]]; then
  NOTES_FILE="$RELEASE_NOTES_DIR/$VERSION.md"
fi

if [[ ! -f "$NOTES_FILE" ]]; then
  mkdir -p "$RELEASE_NOTES_DIR"
  cat <<EOF > "$NOTES_FILE"
# Codigo $VERSION

- Aggiungi qui le note di questa release.
EOF
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist at $INFO_PLIST"
  exit 1
fi

DOWNLOAD_URL="${DOWNLOAD_URL//\{VERSION\}/$VERSION}"
RELEASE_NOTES_URL="https://raw.githubusercontent.com/benjamix95/codigo/main/docs/release-notes/$VERSION.md"
CURRENT_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
SHORT_NOTES="$(head -n 5 "$NOTES_FILE" | tr '\n' ' ')"
ESCAPED_NOTES="$(escape_json "$SHORT_NOTES")"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$INFO_PLIST" \
  >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$INFO_PLIST" \
  >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$INFO_PLIST" \
  >/dev/null 2>&1 || /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 14.0" "$INFO_PLIST"

mkdir -p "$(dirname "$MANIFEST_FILE")"
cat <<EOF > "$MANIFEST_FILE"
{
  "schema": 1,
  "app_name": "Codigo",
  "version": "$VERSION",
  "build": "$BUILD",
  "minimum_system_version": "14.0",
  "release_date": "$CURRENT_DATE",
  "required": false,
  "download_url": "$DOWNLOAD_URL",
  "release_notes": "$ESCAPED_NOTES",
  "release_notes_url": "$RELEASE_NOTES_URL"
}
EOF

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo "Updated release metadata only. Manifest:"
  cat "$MANIFEST_FILE"
  exit 0
fi

build_env=(NOTARIZE="$NOTARIZE")
if [[ -n "$CODESIGN_IDENTITY" ]]; then
  build_env+=(CODESIGN_IDENTITY="$CODESIGN_IDENTITY")
fi
if [[ -n "$NOTARY_KEY_PATH" ]]; then
  build_env+=(NOTARY_KEY_PATH="$NOTARY_KEY_PATH")
fi
if [[ -n "$NOTARY_KEY_ID" ]]; then
  build_env+=(NOTARY_KEY_ID="$NOTARY_KEY_ID")
fi
if [[ -n "$NOTARY_ISSUER_ID" ]]; then
  build_env+=(NOTARY_ISSUER_ID="$NOTARY_ISSUER_ID")
fi
  if [[ -n "$NOTARY_APPLE_ID" ]]; then
  build_env+=(NOTARY_APPLE_ID="$NOTARY_APPLE_ID")
  fi
if [[ -n "$NOTARY_APP_PASSWORD" ]]; then
  build_env+=(NOTARY_APP_PASSWORD="$NOTARY_APP_PASSWORD")
fi
if [[ -n "$NOTARY_TEAM_ID" ]]; then
  build_env+=(NOTARY_TEAM_ID="$NOTARY_TEAM_ID")
fi

env "${build_env[@]}" ./Scripts/build-app.sh
mkdir -p "$REPO_ROOT/dist"
zip -qr "$REPO_ROOT/dist/Codigo-$VERSION.app.zip" Codigo.app
echo "Release package ready at $REPO_ROOT/dist/Codigo-$VERSION.app.zip"
echo "Manifest updated at $MANIFEST_FILE"
