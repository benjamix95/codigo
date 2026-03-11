#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PHASE=""
TAG="review-core-smoke"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    *) echo "Argomento non riconosciuto: $1" >&2; exit 1 ;;
  esac
done

if [[ "$PHASE" != "pre" && "$PHASE" != "post" ]]; then
  echo "Uso: scripts/benchmark_review_pipeline_pre_post.sh --phase pre|post [--tag ID]" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/docs/benchmarks/review-core"
mkdir -p "$OUT_DIR"

ENGINE_JSON="$OUT_DIR/${TAG}-${PHASE}-engine.json"
APP_JSON="$OUT_DIR/${TAG}-${PHASE}-app.json"
SUMMARY_MD="$OUT_DIR/${TAG}-summary.md"

if [[ "$PHASE" == "pre" ]]; then
  export SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1
else
  unset SOLOCODE_REVIEW_CORE_FORCE_SWIFT || true
fi

export SOLOCODE_REVIEW_ENGINE_BENCHMARK_OUTPUT="$ENGINE_JSON"
export SOLOCODE_REVIEW_APP_BENCHMARK_OUTPUT="$APP_JSON"

source "$HOME/.cargo/env"
scripts/build_rust_search_backend.sh >/tmp/solocode-review-rust-build-"$PHASE".log 2>&1 || true
export SOLOCODE_RUST_SKIP_XCODE_BUILD=1
export SOLOCODE_RUST_SEARCH_LIBRARY_PATH="$ROOT_DIR/Native/RustCore/build/lib/libsolocode_rust_core.dylib"

xcodebuild test \
  -workspace 'Solo Code.xcworkspace' \
  -scheme 'Solo Code-Debug' \
  -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/ValidationPerformanceTests/testReviewCoreBridgeSmokeBenchmark \
  -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testReviewPanelStoreSmokeBenchmark \
  >/tmp/solocode-review-benchmark-"$PHASE".log 2>&1

if [[ ! -f "$ENGINE_JSON" ]]; then
  ENGINE_LINE="$(grep 'REVIEW_ENGINE_BENCHMARK ' /tmp/solocode-review-benchmark-"$PHASE".log | tail -n 1 | sed 's/^.*REVIEW_ENGINE_BENCHMARK //')"
  [[ -n "$ENGINE_LINE" ]] && printf '%s\n' "$ENGINE_LINE" >"$ENGINE_JSON"
fi

if [[ ! -f "$APP_JSON" ]]; then
  APP_LINE="$(grep 'REVIEW_APP_BENCHMARK ' /tmp/solocode-review-benchmark-"$PHASE".log | tail -n 1 | sed 's/^.*REVIEW_APP_BENCHMARK //')"
  [[ -n "$APP_LINE" ]] && printf '%s\n' "$APP_LINE" >"$APP_JSON"
fi

/usr/bin/python3 - "$OUT_DIR" "$TAG" "$PHASE" "$ENGINE_JSON" "$APP_JSON" "$SUMMARY_MD" <<'PY'
import json, pathlib, sys

out_dir, tag, phase, engine_json, app_json, summary_md = sys.argv[1:]
engine = json.loads(pathlib.Path(engine_json).read_text())
app = json.loads(pathlib.Path(app_json).read_text())

if phase == "post":
    pre_engine_path = pathlib.Path(out_dir) / f"{tag}-pre-engine.json"
    pre_app_path = pathlib.Path(out_dir) / f"{tag}-pre-app.json"
    if pre_engine_path.exists() and pre_app_path.exists():
        pre_engine = json.loads(pre_engine_path.read_text())
        pre_app = json.loads(pre_app_path.read_text())
        summary = f"""# Review Core Benchmark Summary

- pre engine: `{pre_engine_path}`
- post engine: `{engine_json}`
- pre app: `{pre_app_path}`
- post app: `{app_json}`

## Engine
- verify_candidate_p95_ms: {pre_engine.get('verify_candidate_p95_ms')} -> {engine.get('verify_candidate_p95_ms')}
- verified_sync_p95_ms: {pre_engine.get('verified_sync_p95_ms')} -> {engine.get('verified_sync_p95_ms')}
- audit_suite_duration_ms: {pre_engine.get('audit_suite_duration_ms')} -> {engine.get('audit_suite_duration_ms')}
- rust_review_core_loaded_post: {engine.get('rust_review_core_loaded')}

## App
- snapshot_ingest_p95_ms: {pre_app.get('snapshot_ingest_p95_ms')} -> {app.get('snapshot_ingest_p95_ms')}
- history_load_p95_ms: {pre_app.get('history_load_p95_ms')} -> {app.get('history_load_p95_ms')}
- main_thread_block_time_ms: {pre_app.get('main_thread_block_time_ms')} -> {app.get('main_thread_block_time_ms')}
"""
        pathlib.Path(summary_md).write_text(summary)
PY
