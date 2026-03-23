# P2 — review patch PR e merge result ancora modellati in Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- Dopo il cutover di `prepare_context`, `verify_result`, `apply_result`, `revalidate_result` e `rollback_result`, i lifecycle `open_pr`, `merge_pr` e `resolve_conflicts` continuavano ancora ad avere il risultato canonico dell’artifact modellato in Swift.

## Sintomo
- `ReviewPatchWorkflowService.swift` e `ReviewPatchWorkflowService+Merge.swift` eseguivano Git/PR operations e poi decidevano localmente:
  - `status`
  - `prStatus`
  - `mergeStatus`
  - `branchName`
  - `baseBranchName`
  - `worktreePath`
  - `prURL`
  - `conflicts`

## Impatto
- Ownership ancora sdoppiata sull’ultimo blocco del patch lifecycle prima della chiusura della tranche 4.
- Rust orchestrava già runtime, prepare, verify, apply, revalidate e rollback, ma non ancora le transizioni PR/merge/conflicts.

## Gravità
- `P2`

## Steps to reproduce
1. Eseguire `open_pr`, `merge_pr` o `resolve_conflicts`.
2. Osservare che le operazioni tecniche Git/PR restano Swift.
3. Prima del fix, osservare che anche il risultato finale dell’artifact veniva modellato in Swift.

## Risultato attuale
- Prima del fix, Rust non partecipava allo shaping del risultato canonico dei path PR/merge/conflicts.

## Risultato atteso
- Le operazioni Git e provider AI possono restare Swift in questo batch, ma il risultato finale dell’artifact deve essere derivato dal review core Rust.

## Causa probabile
- Il cutover patch aveva drenato i path di apply/revalidate/rollback ma non ancora il blocco PR/merge/conflicts.

## Scope consentito
- `Native/RustCore/src/review_patch/{open_pr_result.rs,merge_result.rs,resolve_conflicts_result.rs,pr_result_models.rs,mod.rs}`
- `Native/RustCore/src/ffi/review_patch.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/{ReviewPatchWorkflowService.swift,ReviewPatchWorkflowService+Merge.swift}`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Non-scope
- Porting completo di Git/PR execution in Rust
- snapshot upsert canonico patch
- MCP ownership

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`
- `Tests/SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests.swift`
- `Tests/SoloCodeAppTests/ReviewPanelProviderSelectionTests.swift`

## Test da aggiungere o aggiornare
- test Rust sui builder `open_pr_result`, `merge_result`, `resolve_conflicts_result`
- test Swift Rust-gated sul risultato `open_pr`, `merge_pr`, `resolve_conflicts`
- test fail-closed se i runtime relativi non rispondono

## Strategia di fix minimo
- aggiungere builder Rust per i risultati `open_pr`, `merge_pr`, `resolve_conflicts`
- fare chiamare quei builder a `ReviewPatchWorkflowService` e `ReviewPatchWorkflowService+Merge`
- lasciare in Swift solo:
  - worktree lifecycle
  - `git apply`, push, create PR
  - merge GitHub/Git
  - conflict resolution AI

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Commit previsto
- `refactor(review-patch): derive pr and merge results in rust`
