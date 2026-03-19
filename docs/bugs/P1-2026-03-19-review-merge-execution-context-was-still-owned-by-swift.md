# P1 - Il contesto `merge_pr` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift) decideva ancora in Swift il branching semantico di `merge_pr`, cioe' presenza obbligatoria della PR e comportamento `safeOnly -> retry after resolve conflicts`.
- Sintomo:
  - guard locale su `artifact.prURL`
  - scelta locale di `auto: safeOnly` per il primo merge
  - scelta locale di `guard safeOnly else throw`
  - scelta locale di `retry merge` con `auto: false`
- Impatto: il merge lifecycle manteneva ancora decisioni di dominio app-side in una zona fragile di orchestration.
- Gravita': alta, perche' tocca il path di merge/resolve retry e il boundary tra patch state e operazioni Git reali.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift).
  2. Cercare `func mergePullRequest(...)`.
  3. Verificare che precondizione PR e piano `safeOnly/retry` siano ancora nel branching Swift locale.
- Risultato attuale: il contesto esecutivo di merge non e' ancora canonicale in Rust.
- Risultato atteso: Swift deve ricevere dal core Rust `prURL`, `firstMergeAuto`, `retryAfterConflicts`, `retryMergeAuto` e limitarsi a eseguire l'I/O Git.
- Causa probabile: il porting review aveva gia' migrato `mergePullRequestResult`, ma non il blocco che decide come tentare il merge e se fare fallback su `resolve_conflicts`.
- Scope consentito:
  - [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift)
  - [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs)
  - [merge_execution_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/merge_execution_context.rs)
  - [mod.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/mod.rs)
  - [review_patch.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_patch.rs)
  - [ReviewPatchWorkflowServiceTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - merge Git reale
  - conflict resolution AI execution
  - panel runtime
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - `mergePullRequestResult`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression sul nuovo bridge `merge execution context`
  - regression fail-closed quando il runtime Rust e' indisponibile
  - smoke del vecchio `mergePullRequestResult`
- Strategia di fix minimo:
  - aggiungere in Rust `build_merge_execution_context`
  - esporre il boundary `review_core_patch_build_merge_execution_context`
  - sostituire in Swift il branching locale `safeOnly/retry` con il payload Rust
  - allineare i DTO `prUrl` anche sul path merge
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::merge_execution_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testMergePullRequestResultFailsClosedWhenRustRuntimeUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/merge_execution_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route merge execution context through rust`

## Effetto osservato
- Il passo `merge_pr` riceve ora da Rust il piano di esecuzione merge e retry.
- Swift mantiene solo l'I/O Git reale e il fallback su `resolve_conflicts` quando il piano Rust lo consente.
- Il boundary review strict resta senza nuove violazioni.
