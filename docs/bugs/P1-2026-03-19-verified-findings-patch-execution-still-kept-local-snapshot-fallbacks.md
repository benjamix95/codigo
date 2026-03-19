# P1 - `VerifiedFindingsPatchExecutionService` manteneva ancora fallback locali sullo snapshot

## Bug Fix Record
- Categoria: B
- Bug: [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift) manteneva ancora fallback locali nei path `close_finding` e `upsert_patch`.
- Sintomo:
  - fallback manuale da `mutation.findings/events/config`
  - fallback manuale da `mutation.findings/patches/events`
  - ricostruzione locale di `outcome` e `lastUpdatedAt`
- Impatto: restava logica review Swift nel workflow verified findings, nonostante il mutator Rust fornisca già lo snapshot canonico.
- Gravita': alta, perche' tocca il lifecycle patch/finding e la coerenza dello snapshot finale.
- Steps to reproduce:
  1. Aprire [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift).
  2. Cercare `closeFindingWithRustMutation(...)` e `upsertPatchWithRustMutation(...)`.
  3. Verificare la presenza dei fallback locali dopo `if let canonical = mutation.snapshot`.
- Risultato attuale: il service non era ancora completamente passivo verso il mutator Rust.
- Risultato atteso: entrambi i path devono accettare solo lo snapshot canonico Rust o fallire chiuso.
- Causa probabile: i callsite erano rimasti compatibili con versioni precedenti del mutator che non serializzavano ancora sempre `snapshot`.
- Scope consentito:
  - [VerifiedFindingsPatchExecutionService.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift)
  - `ReviewPatchWorkflowServiceTests`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - patch runtime reducers Rust
  - panel runtime
  - review command loop `configure`
- Moduli confinanti da verificare:
  - `ReviewPatchWorkflowServiceTests`
  - strict cutover gate review
- Test da aggiungere o aggiornare:
  - nessun nuovo test necessario; esistono già coperture positive e fail-closed per i due path
- Strategia di fix minimo:
  - rimuovere i fallback locali
  - richiedere `mutation.snapshot` come unico success path
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationUsesRustBridgeWhenAvailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testUpsertPatchSnapshotMutationFailsClosedWhenRustRuntimeUnavailable -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingExecutionClosesMergedFinding -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenRustPatchRuntimeIsDisabled -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests/testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/VerifiedFindingsPatchExecutionService.swift --format text`
- Commit previsto: `refactor(review-patch): require canonical mutation snapshots`

## Effetto osservato
- I path `close_finding` e `upsert_patch` usano ora solo snapshot canonici prodotti dal core Rust.
- Il comportamento fail-closed rimane preservato sui path dove il runtime o il result bridge non sono disponibili.
