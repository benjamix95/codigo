#!/usr/bin/env bash
set -euo pipefail

TRIGGER=""
WORKSPACE=""
FILES_CSV=""
FORMAT="text"
STAGED="false"
REVIEW_CUTOVER_PREFIXES=(
  "App/SoloCodeApp/Sources/Panels/CodeReview"
  "App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview"
  "Engine/CoderEngine/Sources/CodeReview"
  "Engine/CoderEngine/Sources/VerifiedFindingsCore"
  "Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap"
  "Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security"
  "Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter"
)
MAIN_CHAT_CUTOVER_PREFIXES=(
  "App/SoloCodeApp/Sources/Chat/Pipeline"
  "App/SoloCodeApp/Sources/Chat/Store"
  "App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService.swift"
  "App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+ChatPipeline.swift"
  "App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+EventMapping.swift"
  "App/SoloCodeApp/Sources/Runtime/PipelineIntegrationService+EventSupport.swift"
  "App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator.swift"
  "Engine/CoderEngine/Sources/Pipeline/Agents"
  "Engine/CoderEngine/Sources/Pipeline/Bridge"
  "Engine/CoderEngine/Sources/Pipeline/Contracts"
  "Engine/CoderEngine/Sources/Pipeline/EventBus"
  "Engine/CoderEngine/Sources/Pipeline/Locking"
  "Engine/CoderEngine/Sources/Pipeline/Observability"
  "Engine/CoderEngine/Sources/Pipeline/Orchestrator"
  "Engine/CoderEngine/Sources/Pipeline/Scheduler"
  "Engine/CoderEngine/Sources/Pipeline/WorkerPool"
)
ENABLE_MAIN_CHAT_CUTOVER="${SOLOCODE_MAIN_CHAT_CUTOVER:-0}"
ALLOWLIST_PATH="Config/validation/rust-cutover-swift-allowlist.txt"

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

enforced_prefixes=""
baseline_budget_prefixes=""
if [[ -n "$candidate_files" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    for prefix in "${REVIEW_CUTOVER_PREFIXES[@]}"; do
      if [[ "$file" == "$prefix" || "$file" == "$prefix/"* ]]; then
        enforced_prefixes="$(printf '%s\n%s\n' "$enforced_prefixes" "$prefix" | awk 'NF && !seen[$0]++' | paste -sd, -)"
      fi
    done
    if [[ "$ENABLE_MAIN_CHAT_CUTOVER" == "1" ]]; then
      for prefix in "${MAIN_CHAT_CUTOVER_PREFIXES[@]}"; do
        if [[ "$file" == "$prefix" || "$file" == "$prefix/"* ]]; then
          enforced_prefixes="$(printf '%s\n%s\n' "$enforced_prefixes" "$prefix" | awk 'NF && !seen[$0]++' | paste -sd, -)"
        fi
      done
    fi
  done < <(printf '%s\n' "$candidate_files" | tr ',' '\n')
fi

if [[ -n "$enforced_prefixes" ]]; then
  baseline_json_file="$(mktemp "${TMPDIR%/}/review-cutover-baseline-json.XXXXXX")"
  baseline_candidate_files=""
  while IFS= read -r prefix; do
    [[ -z "$prefix" ]] && continue
    prefix_head_files="$(
      git ls-tree -r --name-only HEAD -- "$prefix" |
        rg '\.swift$' |
        paste -sd, - || true
    )"
    if [[ -n "$prefix_head_files" ]]; then
      baseline_candidate_files="$(
        printf '%s\n%s\n' "$baseline_candidate_files" "$prefix_head_files" |
          tr ',' '\n' |
          awk 'NF && !seen[$0]++' |
          paste -sd, -
      )"
    fi
  done < <(printf '%s\n' "$enforced_prefixes" | tr ',' '\n')

  set +e
  cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
    --workspace "$WORKSPACE" \
    --allowlist "$ALLOWLIST_PATH" \
    --candidate-files "$baseline_candidate_files" \
    --enforce-legacy-zero-prefixes "$enforced_prefixes" \
    --include-missing-candidate-files \
    --format json >"$baseline_json_file"
  baseline_status=$?
  set -e
  if [[ "$baseline_status" -ne 0 && "$baseline_status" -ne 2 ]]; then
    cat "$baseline_json_file" >&2
    rm -f "$baseline_json_file"
    exit 1
  fi
  baseline_json="$(cat "$baseline_json_file")"
  if [[ -z "$baseline_json" ]]; then
    rm -f "$baseline_json_file"
    exit 1
  fi

  baseline_budget_prefixes="$(
    python3 - <<'PY' "$baseline_json"
import json
import sys

payload = json.loads(sys.argv[1] or "{}")
counts = payload.get("enforced_prefix_counts") or {}
parts = []
for prefix in sorted(counts):
    budget = max(int(counts[prefix]) - 1, 0)
    parts.append(f"{prefix}={budget}")
print(";".join(parts))
PY
  )"
  rm -f "$baseline_json_file"
fi

cargo test --manifest-path Native/AppCoreRust/Cargo.toml >/tmp/solocode-rust-cutover-guard-tests.log 2>&1 || {
  tail -n 80 /tmp/solocode-rust-cutover-guard-tests.log >&2
  exit 1
}

guard_args=(
  --workspace "$WORKSPACE"
  --allowlist "$ALLOWLIST_PATH"
  --candidate-files "$candidate_files"
  --new-files "$new_files"
  --format "$FORMAT"
)

if [[ -n "$enforced_prefixes" ]]; then
  guard_args+=(--enforce-legacy-zero-prefixes "$enforced_prefixes")
  [[ -n "$baseline_budget_prefixes" ]] && guard_args+=(--legacy-budget-prefixes "$baseline_budget_prefixes")
fi

cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- \
  "${guard_args[@]}" >/tmp/solocode-rust-cutover-guard.log 2>&1 || {
    cat /tmp/solocode-rust-cutover-guard.log >&2
    exit 1
  }

if [[ "$FORMAT" == "text" ]]; then
  cat /tmp/solocode-rust-cutover-guard.log
fi
