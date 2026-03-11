#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CRATE_DIR="$ROOT_DIR/Native/RustCore"
PROFILE="${SOLOCODE_RUST_BUILD_PROFILE:-${CONFIGURATION:-Debug}}"
PROFILE_LOWER="$(printf '%s' "$PROFILE" | tr '[:upper:]' '[:lower:]')"
TARGET_PROFILE="debug"

if [[ "$PROFILE_LOWER" == *release* ]]; then
  TARGET_PROFILE="release"
fi

OUT_DIR="${SOLOCODE_RUST_MANUAL_OUT_DIR:-$CRATE_DIR/build/lib}"
PRODUCTS_OUT="${BUILT_PRODUCTS_DIR:-}/solocode_rust"
LIB_NAME="libsolocode_rust_core"
DYLIB_EXT="dylib"

if ! command -v cargo >/dev/null 2>&1 || ! command -v rustc >/dev/null 2>&1; then
  echo "[rust-search] cargo/rustc non disponibili; backend Rust disattivato"
  exit 0
fi

if [[ ! -f "$CRATE_DIR/Cargo.toml" ]]; then
  echo "[rust-search] crate Rust non trovata in $CRATE_DIR; skip"
  exit 0
fi

mkdir -p "$OUT_DIR"
[[ -n "${BUILT_PRODUCTS_DIR:-}" ]] && mkdir -p "$PRODUCTS_OUT"

BUILD_ARGS=(build --manifest-path "$CRATE_DIR/Cargo.toml")
if [[ "$TARGET_PROFILE" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi

echo "[rust-search] build profilo=$TARGET_PROFILE"
cargo "${BUILD_ARGS[@]}"

ARTIFACT_DIR="$CRATE_DIR/target/$TARGET_PROFILE"
for ext in "$DYLIB_EXT" a; do
  SRC="$ARTIFACT_DIR/$LIB_NAME.$ext"
  if [[ -f "$SRC" ]]; then
    cp "$SRC" "$OUT_DIR/"
    if [[ -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
      cp "$SRC" "$PRODUCTS_OUT/"
    fi
  fi
done

echo "[rust-search] artifact pronti in $OUT_DIR"
