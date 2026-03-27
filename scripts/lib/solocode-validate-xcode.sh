#!/usr/bin/env bash

validation_cache_root() {
  local workspace="$1"
  if [[ -n "${SOLOCODE_VALIDATE_CACHE_ROOT:-}" ]]; then
    printf '%s\n' "$SOLOCODE_VALIDATE_CACHE_ROOT"
    return
  fi

  local workspace_hash
  workspace_hash="$(printf '%s' "$workspace" | shasum -a 256 | awk '{print $1}')"
  printf '%s\n' "${HOME}/Library/Caches/SoloCode/validation/${workspace_hash}"
}

prepare_validation_xcode_paths() {
  local workspace="$1"
  local cache_root
  cache_root="$(validation_cache_root "$workspace")"

  DERIVED_DATA_PATH="${SOLOCODE_VALIDATE_DERIVED_DATA_PATH:-${cache_root}/DerivedData}"
  SOURCE_PACKAGES_DIR="${SOLOCODE_VALIDATE_SOURCE_PACKAGES_DIR:-${workspace}/.xcode-spm-cache}"
  PACKAGE_RESOLVE_STAMP="${SOLOCODE_VALIDATE_PACKAGE_RESOLVE_STAMP:-${cache_root}/package-resolve.stamp}"
  PACKAGE_CACHE_MARKER="${SOLOCODE_VALIDATE_PACKAGE_CACHE_MARKER:-${SOURCE_PACKAGES_DIR}/.solocode-validate-ready}"
  PARALLEL_TESTING_ENABLED="${SOLOCODE_VALIDATE_PARALLEL_TESTING_ENABLED:-YES}"

  mkdir -p "$DERIVED_DATA_PATH" "$SOURCE_PACKAGES_DIR" "$(dirname "$PACKAGE_RESOLVE_STAMP")"
}

latest_package_resolved_mtime() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

workspace = Path(sys.argv[1])
mtimes = []
for path in workspace.rglob("Package.resolved"):
    try:
        mtimes.append(path.stat().st_mtime_ns)
    except FileNotFoundError:
        continue
print(max(mtimes, default=0))
PY
}

package_resolve_stamp_mtime() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
try:
    print(path.stat().st_mtime_ns)
except FileNotFoundError:
    print(0)
PY
}

should_resolve_packages() {
  [[ "${SOLOCODE_XCODE_FORCE_RESOLVE_PACKAGES:-false}" == "true" ]] && return 0
  [[ ! -f "$PACKAGE_CACHE_MARKER" ]] && return 0

  local latest_resolved
  latest_resolved="$(latest_package_resolved_mtime "$1")"
  local stamp_mtime
  stamp_mtime="$(package_resolve_stamp_mtime "$PACKAGE_RESOLVE_STAMP")"
  [[ "$latest_resolved" -gt "$stamp_mtime" ]]
}

mark_package_resolution_ready() {
  mkdir -p "$(dirname "$PACKAGE_CACHE_MARKER")" "$(dirname "$PACKAGE_RESOLVE_STAMP")"
  : > "$PACKAGE_CACHE_MARKER"
  touch "$PACKAGE_RESOLVE_STAMP"
}
