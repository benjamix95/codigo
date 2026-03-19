# P1 - Il contesto `resolve_conflicts` review era ancora owned da Swift

## Bug Fix Record
- Categoria: B
- Bug: [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift) validava ancora in Swift il contesto di `resolve_conflicts` e costruiva localmente il commit message di sync.
- Sintomo:
  - guard locale su `worktreePath`, `branchName`, `baseBranchName`
  - commit message costruito in Swift come `chore(review): sync <branch> with <base>`
- Impatto: il patch workflow manteneva ancora logica di dominio app-side nel passo `resolve_conflicts`, invece di delegare al core Rust il contesto esecutivo prima dell’I/O Git.
- Gravita': alta, perche' tocca un path fragile di orchestration tra worktree, merge no-commit e AI conflict resolution.
- Steps to reproduce:
  1. Aprire [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift).
  2. Cercare `func resolveConflicts(...)`.
  3. Verificare che validazione del contesto e commit message siano ancora locali in Swift.
- Risultato attuale: il contesto `resolve_conflicts` non e' ancora canonicale in Rust.
- Risultato atteso: Swift deve solo eseguire l’I/O Git/AI dopo aver ricevuto dal core Rust un contesto valido e completo.
- Causa probabile: il porting review aveva gia' migrato `resolveConflictsResult`, ma non il blocco precedente che decide se il merge context e' valido e come nominare il commit finale.
- Scope consentito:
  - [ReviewPatchWorkflowService+Merge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift)
  - [pr_result_models.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/pr_result_models.rs)
  - [resolve_conflicts_context.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_patch/resolve_conflicts_context.rs)
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
  - `resolveConflictsResult`
  - boundary Rust `review_patch`
- Test da aggiungere o aggiornare:
  - regression sul nuovo bridge `resolve_conflicts context`
  - regression fail-closed quando il runtime Rust del context non e' disponibile
  - smoke del vecchio `resolveConflictsResult`
- Strategia di fix minimo:
  - aggiungere nel core Rust `build_resolve_conflicts_context`
  - esporre il boundary `review_core_patch_build_resolve_conflicts_context`
  - sostituire il guard Swift con un helper fail-closed che usa il payload Rust
  - passare a Rust anche la derivazione del commit message
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml review_patch::resolve_conflicts_context::tests`
  - `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsExecutionContextUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsExecutionContextFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsResultUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testResolveConflictsResultFailsClosedWhenRustRuntimeUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService+Merge.swift,Native/RustCore/src/review_patch/pr_result_models.rs,Native/RustCore/src/review_patch/resolve_conflicts_context.rs,Native/RustCore/src/review_patch/mod.rs,Native/RustCore/src/ffi/review_patch.rs,Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift --format text`
- Commit previsto: `refactor(review-patch): route resolve conflicts context through rust`

## Effetto osservato
- Il passo `resolve_conflicts` riceve ora da Rust `worktreePath`, `branchName`, `baseBranchName` e `commitMessage`.
- Swift resta solo host di `startNoCommitMerge`, `resolveConflictsAndFixTests`, `finalizeMergeCommit` e `push`.
- Il boundary review strict resta senza nuove violazioni.
