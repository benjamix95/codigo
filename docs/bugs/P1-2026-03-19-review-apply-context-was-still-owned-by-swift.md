# P1 - Il contesto `apply_patch` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift) manteneva ancora in Swift il gating di `apply_patch` e parte del contesto operativo.
- Sintomo:
  - guard locale su `artifact.verifyStatus == .verified`
  - prefix del patch temp file derivato localmente da `artifact.id`
  - parametri operativi di validation (`review_patch_apply`, `workspaceContainsPatch`) ancora locali
- Impatto: il patch lifecycle non era ancora Rust-owned sul boundary di apply execution context e il contratto storico `patchNotVerified` rischiava di degradare in un generico `applyFailed`.
- Gravita': alta, perche' tocca un path core di apply/revert/validation del patch workflow.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift).
  2. Cercare `func applyPatch(...)`.
  3. Verificare che gating di stato e prefix del temp file siano ancora derivati in Swift.
- Risultato attuale: il contesto di apply non e' ancora canonicale in Rust.
- Risultato atteso: Swift deve ricevere dal core Rust il contesto di apply e preservare il contratto pubblico `patchNotVerified`.
- Causa probabile: il porting review aveva gia' migrato `applyPatchResult`, ma non il blocco precedente di precondition/context.
- Scope consentito:
  - [ReviewPatchWorkflowService+ApplyLifecycle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift)
  - [models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/models.rs)
  - [apply_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/apply_execution_context.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - Git apply/revert reale
  - validation pipeline
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `applyPatchResult`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression su `apply execution context`
  - fail-closed quando il runtime Rust non e' disponibile
  - preservare il contratto `patchNotVerified` nel path reale `applyPatch(...)`
- Strategia di fix minimo:
  - aggiungere in Rust `build_apply_execution_context`
  - esporre il boundary `review_core_patch_build_apply_execution_context`
  - instradare `applyPatch(...)` attraverso il nuovo bridge
  - preservare `patchNotVerified` mappando il messaggio Rust sul contratto storico
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::apply_execution_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchRejectsArtifactThatWasNotVerified -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testApplyPatchResultFailsClosedWhenRustRuntimeUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+ApplyLifecycle.swift,Native/RustCore/src/review_patch/models.rs,Native/RustCore/src/review_patch/apply_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route apply execution context through rust`

## Effetto osservato
- `apply_patch` usa ora un execution context Rust fail-closed.
- Swift non mantiene piu' il gating locale su `verifyStatus` e il prefix del temp patch file.
- Il contratto osservabile `patchNotVerified` resta preservato.
