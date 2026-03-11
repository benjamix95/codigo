# 2026-03-11 — Review patch runtime stateful Rust tranche

## Scope
- runtime patch stateful nel core Rust
- riduzione del branching residuo nei wrapper lifecycle review/security/bughunter

## Modifiche
- aggiunto `Native/RustCore/src/review_patch/runtime.rs`
- estesi `Native/RustCore/src/review_patch/models.rs` e `Native/RustCore/src/ffi.rs` con:
  - `review_core_patch_start_runtime`
  - `review_core_patch_apply_runtime_result`
  - `review_core_patch_get_runtime_state`
- esteso `ReviewPatchRustBridge` con API runtime step-based
- aggiornato `VerifiedFindingsPatchExecutionService` per eseguire il patch flow tramite runtime Rust, non più solo da piano statico
- introdotto `queueCommand(...)` in `VerifiedFindingsLifecycleCommandService`
- ridotti `SecurityWorkflowService` e `BugHunterWorkflowService` a wrapper più sottili sul lifecycle service condiviso

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- tentata validazione `xcodebuild test` sulle suite mirate review

## Note
- `Native/RustCore/target/` resta fuori dai commit
- il runner Xcode può fallire prima della compilazione per un problema host-side su `IDESimulatorFoundation/CoreSimulator`; non è un errore del codice del repo
