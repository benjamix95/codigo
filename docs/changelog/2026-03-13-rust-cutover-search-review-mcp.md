# 2026-03-13 - Rust cutover search/review/MCP launcher

## Modifiche
- reso `RustSearchEngineBackend` il backend predefinito della semantic search quando non e' richiesto esplicitamente il backend Swift
- rimosso il fallback automatico a `SwiftSearchEngineBackend`; se il core Rust non e' disponibile la search fallisce con errore esplicito e senza risultati
- rimosso il path euristico locale Swift da `ReviewCandidateVerificationService`; la verifica automatica dei candidate ora richiede il review core Rust
- eliminato l'override `SOLOCODE_USE_SWIFT_MCP_SERVER` dal launcher `CoderIDEMCPServerExecutable`, che ora execva sempre il binario Rust

## Test
- aggiornati `SearchEngineBackendTests` per verificare:
  - default Rust
  - parity Rust/Swift quando Rust e' disponibile
  - failure esplicito senza fallback quando Rust e' disabilitato
- aggiornati `ReviewCandidateVerificationServiceTests` per verificare:
  - semantica Rust sui casi coperti
  - failure esplicito `rust_core_unavailable` quando il core Rust e' disabilitato
- eseguito `cargo test --manifest-path Native/RustCore/Cargo.toml review_verify -- --nocapture`
- esecuzione `xcodebuild` mirata su `SearchEngineBackendTests` e `ReviewCandidateVerificationServiceTests` avviata per validazione del tranche

## Impatto
- il progetto e' piu' vicino a un ownership model coerente: non-UI search/review non ricade piu' automaticamente su business logic Swift
- il cutover ora e' piu' severo: assenza del core Rust emerge come errore esplicito invece di restare nascosta dietro fallback locali
