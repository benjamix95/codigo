# 2026-03-23 — Review audit rust missing bug tools

## Modifiche
- aggiunto supporto Rust per `audit_bug_test_gaps`, `audit_bug_state_machine` e `audit_bug_error_handling` in [review_audit.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_audit.rs)
- mantenuto il formato payload/summary coerente con gli altri audit rust-backed
- aggiunta regressione che verifica che i tre tool non rispondano piu' con `unsupported_tool`

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml review_audit -- --nocapture`

## Diagnostica correlata
- raccolto sample del processo app bloccato in `/tmp/solocode-sample-5283.txt`
- il sample indica un blocco del main thread nel path di persistenza review + bootstrap Postgres; bug tracciato separatamente in `docs/bugs/P1-2026-03-23-solocode-main-thread-freeze-on-review-persistence.md`
