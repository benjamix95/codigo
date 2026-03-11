# Review Core Benchmark Summary

- pre engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche3-pre-engine.json`
- post engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche3-post-engine.json`
- pre app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche3-pre-app.json`
- post app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche3-post-app.json`

## Engine
- verify_candidate_p95_ms: 0.2090930938720703 -> 0.1329183578491211
- verified_sync_p95_ms: 0.1310110092163086 -> 18.409013748168945
- projection_build_p95_ms: 0.7340908050537109 -> 6.3010454177856445
- security_gate_p95_ms: 1.6069412231445312 -> 12.819051742553711
- historical_shape_p95_ms: 0.19991397857666016 -> 4.696011543273926
- audit_suite_duration_ms: 0.2690553665161133 -> 0.20599365234375
- rust_review_core_loaded_post: True
- rust_review_core_failure_reason_post: 

## App
- snapshot_ingest_p95_ms: 1.2079477310180664 -> 1.0039806365966797
- history_load_p95_ms: 4.979968070983887 -> 6.576061248779297
- main_thread_block_time_ms: 1.2309551239013672 -> 1.1550188064575195
