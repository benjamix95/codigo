# 2026-03-11 — Pulizia warning residui del review core Rust

## Modifiche
- rimossi import inutilizzati in `review_mcp/review.rs` e `review_pipeline/scope.rs`
- rimossi helper morti in `review_value.rs`
- rimossi helper morti in `review_mcp/models.rs`
- marcato `ReviewPipelineCallbackResult` come struttura con campi compat-only per evitare warning fuorvianti

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`

## Esito
- il crate `solocode_rust_core` compila e passa i test senza warning residui del delta locale
