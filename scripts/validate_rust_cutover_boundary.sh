#!/usr/bin/env bash
set -euo pipefail

TRIGGER=""
WORKSPACE=""
FILES_CSV=""
FORMAT="text"
STAGED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trigger) TRIGGER="$2"; shift 2 ;;
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --files) FILES_CSV="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-text}"; shift 2 ;;
    --staged) STAGED="true"; shift ;;
    *) echo "Unknown argument for validate_rust_cutover_boundary.sh: $1" >&2; exit 1 ;;
  esac
done

cd "$WORKSPACE"

candidate_files="$FILES_CSV"
if [[ -z "$candidate_files" && "$STAGED" == "true" ]]; then
  candidate_files="$(git diff --cached --name-only --diff-filter=ACMR | paste -sd, -)"
fi
if [[ -z "$candidate_files" && "$TRIGGER" == "ciFull" ]] && git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  candidate_files="$(git diff --name-only --diff-filter=ACMR HEAD^ HEAD | paste -sd, -)"
fi

new_files=""
if [[ "$STAGED" == "true" ]]; then
  new_files="$(git diff --cached --name-status --diff-filter=A | awk '{print $2}' | paste -sd, -)"
elif [[ "$TRIGGER" == "ciFull" ]] && git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  new_files="$(git diff --name-status --diff-filter=A HEAD^ HEAD | awk '{print $2}' | paste -sd, -)"
elif [[ -n "$candidate_files" ]]; then
  new_files="$(
    git status --porcelain -- $(printf '%s\n' "$candidate_files" | tr ',' ' ') |
      awk '
        /^\?\? / { print $2 }
        /^A  / { print $2 }
        /^AM / { print $2 }
      ' | paste -sd, -
  )"
fi

if [[ -n "$candidate_files" ]]; then
  swift_candidate_count="$(printf '%s\n' "$candidate_files" | tr ',' '\n' | rg -c '\.swift$' || true)"
  [[ "$swift_candidate_count" == "0" ]] && exit 0
fi

cargo test --manifest-path Native/AppCoreRust/Cargo.toml >/tmp/solocode-rust-cutover-guard-tests.log 2>&1 || {
  tail -n 80 /tmp/solocode-rust-cutover-guard-tests.log >&2
  exit 1
}

cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  --workspace "$WORKSPACE" \
  --allowlist "Config/validation/rust-cutover-swift-allowlist.txt" \
  --candidate-files "$candidate_files" \
  --new-files "$new_files" \
  --format "$FORMAT" >/tmp/solocode-rust-cutover-guard.log 2>&1 || {
    cat /tmp/solocode-rust-cutover-guard.log >&2
    exit 1
  }

if [[ "$FORMAT" == "text" ]]; then
  cat /tmp/solocode-rust-cutover-guard.log
fi
