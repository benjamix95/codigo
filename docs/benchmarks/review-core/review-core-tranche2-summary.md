# Review Core Benchmark Summary

- pre engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche2-pre-engine.json`
- post engine: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche2-post-engine.json`
- pre app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche2-pre-app.json`
- post app: `/Users/benjaminstoica/SoloCode/docs/benchmarks/review-core/review-core-tranche2-post-app.json`

## Engine
- verify_candidate_p95_ms: 0.32591819763183594 -> 0.1690387725830078
- verified_sync_p95_ms: 0.20503997802734375 -> 11.902928352355957
- projection_build_p95_ms: 0.8299350738525391 -> 6.670951843261719
- security_gate_p95_ms: 2.3660659790039062 -> 11.718988418579102
- historical_shape_p95_ms: 0.247955322265625 -> 4.312992095947266
- audit_suite_duration_ms: 0.3739595413208008 -> 0.26702880859375
- rust_review_core_loaded_post: True
- rust_review_core_failure_reason_post: 

## App
- snapshot_ingest_p95_ms: 1.028895378112793 -> 1.1320114135742188
- history_load_p95_ms: 2.599954605102539 -> 12.835979461669922
- main_thread_block_time_ms: 1.0579824447631836 -> 1.2210607528686523
