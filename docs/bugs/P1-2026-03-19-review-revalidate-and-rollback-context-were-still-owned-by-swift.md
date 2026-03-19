# P1 - I context `revalidate_patch` e `rollback_patch` review erano ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) manteneva ancora in Swift le precondizioni di `revalidate_patch` e `rollback_patch`.
- Sintomo:
  - `revalidatePatch(...)` verificava localmente `artifact.status == .applied`
  - `rollbackPatch(...)` verificava localmente `artifact.status == .applied` e `artifact.rollbackRef != nil`
  - il prefix del file temporaneo di rollback veniva costruito localmente
- Impatto: il patch lifecycle non era ancora Rust-owned sulle precondizioni di revalidate/rollback, in una zona fragile tra stato patch, validation e apply reverse.
- Gravita': alta, perche' tocca percorsi di mutazione del patch artifact e fallback fail-closed del runtime Rust.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift).
  2. Cercare `func revalidatePatch(...)` e `func rollbackPatch(...)`.
  3. Verificare che le precondizioni e il prefix di rollback siano ancora locali in Swift.
- Risultato attuale: il contesto esecutivo di revalidate/rollback non e' ancora canonicale in Rust.
- Risultato atteso: Swift deve ricevere da Rust un execution context valido o fallire chiuso.
- Causa probabile: il porting review aveva gia' migrato i result reducer di `revalidate` e `rollback`, ma non i blocchi precedenti di gating/precondition.
- Scope consentito:
  - [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift)
  - [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs)
  - [revalidate_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/revalidate_execution_context.rs)
  - [rollback_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/rollback_execution_context.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - validation pipeline
  - Git apply/reverse apply reale
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `revalidatePatchResult`
  - `rollbackPatchResult`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression su `revalidate execution context`
  - regression su `rollback execution context`
  - fail-closed per entrambi
- Strategia di fix minimo:
  - aggiungere in Rust `build_revalidate_execution_context`
  - aggiungere in Rust `build_rollback_execution_context`
  - esporre entrambi i boundary FFI
  - instradare `revalidatePatch(...)` e `rollbackPatch(...)` attraverso helper fail-closed
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::revalidate_execution_context::tests`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::rollback_execution_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRevalidatePatchResultFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testRollbackPatchResultFailsClosedWhenRustRuntimeUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/revalidate_execution_context.rs,Native/RustCore/src/review_patch/rollback_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route rollback and revalidate context through rust`

## Effetto osservato
- `revalidate_patch` e `rollback_patch` usano ora execution context Rust fail-closed.
- Swift non mantiene piu' localmente il gating di stato e il prefix del rollback temp file.
- Il boundary review strict resta senza nuove violazioni.
