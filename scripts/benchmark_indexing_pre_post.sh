#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$ROOT_DIR/docs/benchmarks/indexing-hardening"

PHASE=""
TAG=""
RUNS="6"
WARMUP="2"
FILES="180"

usage() {
  cat <<'EOF'
Usage:
  scripts/benchmark_indexing_pre_post.sh --phase pre|post [--tag ID] [--runs N] [--warmup N] [--files N]

Examples:
  scripts/benchmark_indexing_pre_post.sh --phase pre --tag I13-I19
  scripts/benchmark_indexing_pre_post.sh --phase post --tag I13-I19
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --runs) RUNS="${2:-}"; shift 2 ;;
    --warmup) WARMUP="${2:-}"; shift 2 ;;
    --files) FILES="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argomento non riconosciuto: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$PHASE" != "pre" && "$PHASE" != "post" ]]; then
  echo "Errore: --phase deve essere pre o post" >&2
  usage
  exit 1
fi

if [[ -z "$TAG" ]]; then
  TAG="$(date -u +"%Y%m%dT%H%M%SZ")"
fi

mkdir -p "$BENCH_DIR"
mkdir -p "$ROOT_DIR/tmp"

OUTPUT_JSON="$BENCH_DIR/${TAG}-${PHASE}.json"
LOG_FILE="$BENCH_DIR/${TAG}-${PHASE}.log"
CONFIG_FILE="$ROOT_DIR/tmp/index-benchmark-config.json"

cat > "$CONFIG_FILE" <<EOF
{"phase":"$PHASE","runs":$RUNS,"warmup_runs":$WARMUP,"files":$FILES,"output_path":"$OUTPUT_JSON"}
EOF
trap 'rm -f "$CONFIG_FILE"' EXIT

echo "==> Eseguo benchmark $PHASE (tag=$TAG, runs=$RUNS, warmup=$WARMUP, files=$FILES)"
(
  RUN_INDEX_BENCHMARK_SMOKE=1 \
  xcodebuild test \
    -project 'Solo Code.xcodeproj' \
    -scheme 'CoderEngineTests-Debug' \
    -destination 'platform=macOS' \
    -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke
) | tee "$LOG_FILE"

if [[ ! -f "$OUTPUT_JSON" ]]; then
  LOG_JSON="$(grep 'INDEX_BENCHMARK_SMOKE_RESULT=' "$LOG_FILE" | tail -n 1 | sed 's/^.*INDEX_BENCHMARK_SMOKE_RESULT=//')"
  if [[ -n "$LOG_JSON" ]]; then
    printf '%s\n' "$LOG_JSON" > "$OUTPUT_JSON"
  else
    echo "Errore: output benchmark non trovato in $OUTPUT_JSON" >&2
    exit 1
  fi
fi

echo "==> JSON scritto: $OUTPUT_JSON"
echo "==> Log scritto:  $LOG_FILE"

extract_json_number() {
  local file="$1"
  local key="$2"
  sed -nE "s/.*\"$key\":([0-9]+).*/\1/p" "$file"
}

percent_delta() {
  local from="$1"
  local to="$2"
  awk "BEGIN { if ($from == 0) { print \"n/a\" } else { printf \"%.2f%%\", (($to - $from) / $from) * 100 } }"
}

if [[ "$PHASE" == "post" ]]; then
  PRE_JSON="$BENCH_DIR/${TAG}-pre.json"
  if [[ -f "$PRE_JSON" ]]; then
    pre_full="$(extract_json_number "$PRE_JSON" "full_median_ms")"
    post_full="$(extract_json_number "$OUTPUT_JSON" "full_median_ms")"
    pre_inc="$(extract_json_number "$PRE_JSON" "incremental_median_ms")"
    post_inc="$(extract_json_number "$OUTPUT_JSON" "incremental_median_ms")"

    SUMMARY_MD="$BENCH_DIR/${TAG}-summary.md"
    cat > "$SUMMARY_MD" <<EOF
# Indexing Hardening Benchmark - $TAG

| KPI | pre | post | delta |
|---|---:|---:|---:|
| full_median_ms | $pre_full | $post_full | $(percent_delta "$pre_full" "$post_full") |
| incremental_median_ms | $pre_inc | $post_inc | $(percent_delta "$pre_inc" "$post_inc") |

Artifacts:
- pre: \`$PRE_JSON\`
- post: \`$OUTPUT_JSON\`
- logs: \`$BENCH_DIR/${TAG}-pre.log\`, \`$LOG_FILE\`
EOF
    echo "==> Summary scritto: $SUMMARY_MD"
  else
    echo "==> Nessun pre trovato per tag $TAG (atteso: $PRE_JSON)."
  fi
fi
