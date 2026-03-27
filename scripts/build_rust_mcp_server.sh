#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CRATE_DIR="$ROOT_DIR/Native/CoderideMCPServerRust"
PROFILE="${SOLOCODE_RUST_MCP_BUILD_PROFILE:-${CONFIGURATION:-Debug}}"
PROFILE_LOWER="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
TARGET_PROFILE="debug"
STAMP_ROOT="${SOLOCODE_RUST_MCP_TEST_OUT_DIR:-$ROOT_DIR/.build/rust-mcp-server/$TARGET_PROFILE}"
STAMP_FILE="$STAMP_ROOT/.build-rust-mcp-server-$TARGET_PROFILE.stamp"

if [[ "$PROFILE_LOWER" == *release* ]]; then
  TARGET_PROFILE="release"
fi

resolve_rust_toolchain() {
  if command -v cargo >/dev/null 2>&1 && command -v rustc >/dev/null 2>&1; then
    return 0
  fi

  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    . "$HOME/.cargo/env"
  fi

  for dir in "$HOME/.cargo/bin" /usr/local/bin /opt/homebrew/bin; do
    if [[ -x "$dir/cargo" && -x "$dir/rustc" ]]; then
      export PATH="$dir:$PATH"
      return 0
    fi
  done

  return 1
}

if ! resolve_rust_toolchain; then
  echo "[rust-mcp] cargo/rustc non disponibili nel PATH né in posizioni standard (~/.cargo/bin, /usr/local/bin, /opt/homebrew/bin)"
  exit 1
fi

if [[ ! -f "$CRATE_DIR/Cargo.toml" ]]; then
  echo "[rust-mcp] crate Rust non trovata in $CRATE_DIR"
  exit 1
fi

needs_rebuild() {
  local stamp_file="$1"
  shift

  if [[ ! -f "$stamp_file" ]]; then
    return 0
  fi

  for path in "$@"; do
    if [[ -d "$path" ]]; then
      if find "$path" -type f -newer "$stamp_file" -print -quit | grep -q .; then
        return 0
      fi
    elif [[ -f "$path" && "$path" -nt "$stamp_file" ]]; then
      return 0
    fi
  done
  return 1
}

PRIMARY_OUTPUT="$ROOT_DIR/.build/rust-mcp-server/$TARGET_PROFILE/coderide-mcp-server-rust"
if [[ -f "$PRIMARY_OUTPUT" ]] && ! needs_rebuild "$STAMP_FILE" \
  "$CRATE_DIR/Cargo.toml" \
  "$CRATE_DIR/src" \
  "$ROOT_DIR/Native/Cargo.toml" \
  "$ROOT_DIR/scripts/build_rust_mcp_server.sh"; then
  echo "[rust-mcp] artifact gia' aggiornato, skip build"
  exit 0
fi

BUILD_ARGS=(build --manifest-path "$CRATE_DIR/Cargo.toml")
if [[ "$TARGET_PROFILE" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi

echo "[rust-mcp] build profilo=$TARGET_PROFILE"
cargo "${BUILD_ARGS[@]}"

ARTIFACT_DIR="$ROOT_DIR/Native/target/$TARGET_PROFILE"
SRC="$ARTIFACT_DIR/coderide-mcp-server-rust"
if [[ ! -x "$SRC" ]]; then
  echo "[rust-mcp] artifact mancante: $SRC"
  exit 1
fi

TEST_OUT_DIR="${SOLOCODE_RUST_MCP_TEST_OUT_DIR:-$ROOT_DIR/.build/rust-mcp-server/$TARGET_PROFILE}"
mkdir -p "$TEST_OUT_DIR"
cp "$SRC" "$TEST_OUT_DIR/coderide-mcp-server-rust"
# Strip resource forks and com.apple.provenance that break codesign
xattr -cr "$TEST_OUT_DIR/coderide-mcp-server-rust" 2>/dev/null || true

if [[ -n "${SOLOCODE_MCP_SERVER_BUNDLE_DIR:-}" ]]; then
  mkdir -p "$SOLOCODE_MCP_SERVER_BUNDLE_DIR"
  cp "$SRC" "$SOLOCODE_MCP_SERVER_BUNDLE_DIR/coderide-mcp-server-rust"
  xattr -cr "$SOLOCODE_MCP_SERVER_BUNDLE_DIR/coderide-mcp-server-rust" 2>/dev/null || true
  chmod +x "$SOLOCODE_MCP_SERVER_BUNDLE_DIR/coderide-mcp-server-rust"
fi

touch "$STAMP_FILE"

echo "[rust-mcp] artifact pronti in $TEST_OUT_DIR"
