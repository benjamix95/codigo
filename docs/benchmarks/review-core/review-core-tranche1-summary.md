# Review Core Benchmark Summary

- pre engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche1-pre-engine.json`
- post engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche1-post-engine.json`
- pre app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche1-pre-app.json`
- post app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche1-post-app.json`

## Engine
- verify_candidate_p95_ms: 0.06604194641113281 -> 0.11301040649414062
- verified_sync_p95_ms: 0.02300739288330078 -> 0.01704692840576172
- audit_suite_duration_ms: 0.0959634780883789 -> 0.0820159912109375
- rust_review_core_loaded_post: False

## App
- snapshot_ingest_p95_ms: 0.053048133850097656 -> 0.051975250244140625
- history_load_p95_ms: 1.6880035400390625 -> 5.414009094238281
- main_thread_block_time_ms: 0.41806697845458984 -> 0.3859996795654297
