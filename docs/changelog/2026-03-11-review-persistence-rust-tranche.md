# 2026-03-11 — Persistence review/bughunter instradata sul core Rust

## Modifiche
- aggiunto il nuovo dominio Rust `review_persistence` con codec per:
  - review snapshot
  - bughunter snapshot
  - review commands
  - bughunter commands
  - review index
- estesi gli entrypoint FFI in `Native/RustCore/src/ffi.rs` con le API `review_core_persistence_*`
- introdotto `ReviewPersistenceRustAdapter` lato Swift
- `MCPSharedState+CodeReview`, `MCPSharedState+BugHunter`, `MCPSharedState+CodeReviewCommands` e `MCPSharedState+BugHunterCommands` usano ora l’adapter Rust per encode/decode dei payload persistiti
- `PostgresPersistenceStore+ReviewAndPlan` usa ora l’adapter Rust per serializzare review snapshot e bughunter snapshot prima della persistenza

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`

## Esito
- il boundary persistence review/bughunter non è più interamente shape-built in Swift
- la queue review/bughunter e gli snapshot persistiti passano da codec Rust canonici
- il command loop app-side resta ancora da chiudere come orchestration, ma ora usa già payload persistiti più coerenti col core Rust
