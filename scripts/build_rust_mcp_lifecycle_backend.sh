#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CRATE_DIR="$ROOT_DIR/Native/MCPLifecycleBackendRust"
PROFILE="${SOLOCODE_RUST_MCP_LIFECYCLE_BUILD_PROFILE:-${CONFIGURATION:-Debug}}"
PROFILE_LOWER="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
TARGET_PROFILE="debug"

if [[ "$PROFILE_LOWER" == *release* ]]; then
  TARGET_PROFILE="release"
fi

if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
  echo "[rust-mcp-lifecycle] cargo/rustc non disponibili"
  exit 1
fi

if [[ ! -f "$CRATE_DIR/Cargo.toml" ]]; then
  echo "[rust-mcp-lifecycle] crate Rust non trovata in $CRATE_DIR"
  exit 1
fi

BUILD_ARGS=(build --manifest-path "$CRATE_DIR/Cargo.toml" --bins)
if [[ "$TARGET_PROFILE" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi

echo "[rust-mcp-lifecycle] build profilo=$TARGET_PROFILE"
cargo "${BUILD_ARGS[@]}"

ARTIFACT_DIR="$ROOT_DIR/Native/target/$TARGET_PROFILE"
SRC="$ARTIFACT_DIR/mcp-lifecycle-backend-rust"
FAKE_SRC="$ARTIFACT_DIR/fake-mcp-server"
if [[ ! -x "$SRC" ]]; then
  echo "[rust-mcp-lifecycle] artifact mancante: $SRC"
  exit 1
fi

TEST_OUT_DIR="${SOLOCODE_RUST_MCP_LIFECYCLE_TEST_OUT_DIR:-$ROOT_DIR/.build/rust-mcp-lifecycle/$TARGET_PROFILE}"
mkdir -p "$TEST_OUT_DIR"
cp "$SRC" "$TEST_OUT_DIR/mcp-lifecycle-backend-rust"
if [[ -x "$FAKE_SRC" ]]; then
  cp "$FAKE_SRC" "$TEST_OUT_DIR/fake-mcp-server"
fi

if [[ -n "${SOLOCODE_MCP_SERVER_BUNDLE_DIR:-}" ]]; then
  mkdir -p "$SOLOCODE_MCP_SERVER_BUNDLE_DIR"
  cp "$SRC" "$SOLOCODE_MCP_SERVER_BUNDLE_DIR/mcp-lifecycle-backend-rust"
  chmod +x "$SOLOCODE_MCP_SERVER_BUNDLE_DIR/mcp-lifecycle-backend-rust"
fi

echo "[rust-mcp-lifecycle] artifact pronti in $TEST_OUT_DIR"
