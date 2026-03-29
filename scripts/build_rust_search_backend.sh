#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CRATE_DIR="$ROOT_DIR/Native/RustCore"
PROFILE="${SOLOCODE_RUST_BUILD_PROFILE:-${CONFIGURATION:-Debug}}"
PROFILE_LOWER="$(printf '%s' "$PROFILE" | /usr/bin/tr '[:upper:]' '[:lower:]')"
TARGET_PROFILE="debug"

if [[ "$PROFILE_LOWER" == *release* ]]; then
  TARGET_PROFILE="release"
fi

OUT_DIR="${SOLOCODE_RUST_MANUAL_OUT_DIR:-$CRATE_DIR/build/lib}"
PRODUCTS_OUT="${BUILT_PRODUCTS_DIR:-}/solocode_rust"
BUNDLE_OUT="${SOLOCODE_RUST_REVIEW_CORE_BUNDLE_DIR:-}"
LIB_NAME="libsolocode_rust_core"
DYLIB_EXT="dylib"
STAMP_FILE="$OUT_DIR/.build-rust-search-$TARGET_PROFILE.stamp"

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

copy_artifact() {
  local src="$1"
  local dest_dir="$2"
  local dest_name="${3:-$(basename "$src")}"
  local tmp_path="$dest_dir/.${dest_name}.tmp.$$"
  local dest_path="$dest_dir/$dest_name"

  mkdir -p "$dest_dir"
  rm -f "$tmp_path"
  cp "$src" "$tmp_path"

  # Strip resource forks and com.apple.provenance that break codesign
  xattr -cr "$tmp_path" 2>/dev/null || true

  if [[ "$dest_name" == *".dylib" ]]; then
    if ! codesign --force --sign - "$tmp_path" >/dev/null 2>&1; then
      rm -f "$tmp_path"
      echo "[rust-search] impossibile firmare $dest_name dopo la copia in $dest_dir" >&2
      exit 1
    fi
  fi

  mv -f "$tmp_path" "$dest_path"
}

copy_cached_outputs() {
  local dylib_src="$OUT_DIR/$LIB_NAME.$DYLIB_EXT"
  local static_src="$OUT_DIR/$LIB_NAME.a"

  if [[ -f "$dylib_src" && -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
    copy_artifact "$dylib_src" "$PRODUCTS_OUT"
  fi
  if [[ -f "$static_src" && -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
    copy_artifact "$static_src" "$PRODUCTS_OUT"
  fi
  if [[ -f "$dylib_src" && -n "$BUNDLE_OUT" ]]; then
    copy_artifact "$dylib_src" "$BUNDLE_OUT"
  fi
}

resolve_cargo() {
  command -v cargo 2>/dev/null && return 0
  for p in "$HOME/.cargo/bin/cargo" /usr/local/bin/cargo /opt/homebrew/bin/cargo; do
    if [[ -x "$p" ]]; then
      export PATH="$(dirname "$p"):$PATH"
      return 0
    fi
  done
  return 1
}

if ! resolve_cargo || ! command -v rustc >/dev/null 2>&1; then
  if [[ -n "$BUNDLE_OUT" ]]; then
    echo "[rust-search] review core Rust richiesto per il bundle, ma cargo/rustc non sono disponibili nel PATH né in posizioni standard (~/.cargo/bin, /usr/local/bin, /opt/homebrew/bin)." >&2
    exit 1
  fi
  echo "warning: [rust-search] cargo/rustc non trovati nel PATH né in posizioni standard (~/.cargo/bin, /usr/local/bin, /opt/homebrew/bin). La dylib Rust NON verrà compilata." >&2
  exit 0
fi

if [[ ! -f "$CRATE_DIR/Cargo.toml" ]]; then
  echo "[rust-search] crate Rust non trovata in $CRATE_DIR; skip"
  exit 0
fi

mkdir -p "$OUT_DIR"
[[ -n "${BUILT_PRODUCTS_DIR:-}" ]] && mkdir -p "$PRODUCTS_OUT"
[[ -n "$BUNDLE_OUT" ]] && mkdir -p "$BUNDLE_OUT"

PRIMARY_OUTPUT="$OUT_DIR/$LIB_NAME.$DYLIB_EXT"
if [[ -f "$PRIMARY_OUTPUT" ]] && ! needs_rebuild "$STAMP_FILE" \
  "$CRATE_DIR/Cargo.toml" \
  "$CRATE_DIR/src" \
  "$ROOT_DIR/Native/Cargo.toml" \
  "$ROOT_DIR/scripts/build_rust_search_backend.sh"; then
  copy_cached_outputs
  echo "[rust-search] artifact gia' aggiornato, skip build"
  exit 0
fi

BUILD_ARGS=(build --manifest-path "$CRATE_DIR/Cargo.toml")
if [[ "$TARGET_PROFILE" == "release" ]]; then
  BUILD_ARGS+=(--release)
fi

echo "[rust-search] build profilo=$TARGET_PROFILE"
cargo "${BUILD_ARGS[@]}"

ARTIFACT_DIRS=(
  "$ROOT_DIR/Native/target/$TARGET_PROFILE"
  "$CRATE_DIR/target/$TARGET_PROFILE"
)
copied_dylib=0
for ext in "$DYLIB_EXT" a; do
  for ARTIFACT_DIR in "${ARTIFACT_DIRS[@]}"; do
    SRC="$ARTIFACT_DIR/$LIB_NAME.$ext"
    if [[ -f "$SRC" ]]; then
      copy_artifact "$SRC" "$OUT_DIR"
      if [[ -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
        copy_artifact "$SRC" "$PRODUCTS_OUT"
      fi
      if [[ -n "$BUNDLE_OUT" && "$ext" == "$DYLIB_EXT" ]]; then
        copy_artifact "$SRC" "$BUNDLE_OUT"
      fi
      if [[ "$ext" == "$DYLIB_EXT" ]]; then
        copied_dylib=1
      fi
      break
    fi
  done
done

if [[ "$copied_dylib" -ne 1 ]]; then
  echo "[rust-search] artifact dylib mancante: cercato $LIB_NAME.$DYLIB_EXT in ${ARTIFACT_DIRS[*]}" >&2
  exit 1
fi

touch "$STAMP_FILE"

echo "[rust-search] artifact pronti in $OUT_DIR"
