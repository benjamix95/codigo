# P1 - Il panel review ricostruiva ancora in Swift lo snapshot post-mutation

## Bug Fix Record
- Categoria: B
- Bug: [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift) ricostruiva ancora localmente `findings/events/outcome` dopo `review_core_command_mutate_snapshot`.
- Sintomo:
  - `snapshot.copying(findings: findings, events: events, outcome: ...)`
  - `buildOutcomeSummary()` nel panel runtime
  anche se il core Rust puo' gia' produrre lo snapshot canonico.
- Impatto: restava logica di dominio Swift nel panel runtime su un path che dovrebbe essere puro binding/snapshot ingestion.
- Gravita': alta, perche' tocca il sincronismo tra panel session state, task activity snapshot e outcome review.
- Steps to reproduce:
  1. Aprire [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift).
  2. Cercare il branch che gestisce `review_core_command_mutate_snapshot`.
  3. Verificare che il panel ricrei ancora lo snapshot finale in Swift quando il bridge Rust risponde.
- Risultato attuale: il panel non usa ancora sistematicamente lo snapshot canonico Rust.
- Risultato atteso: se il mutator Rust restituisce `snapshot`, il panel deve ingerire quello direttamente e non ricostruire `outcome` localmente.
- Causa probabile: il panel era rimasto allineato al vecchio contratto mutation-by-slices (`findings/events`) e non al nuovo snapshot canonico completo.
- Scope consentito:
  - [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - review panel chat runtime
  - prompt building panel
  - provider selection panel
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - `ReviewPatchWorkflowServiceTests` sui dismiss live-state
- Test da aggiungere o aggiornare:
  - usare i test panel e live dismiss gia' esistenti come smoke di regressione
- Strategia di fix minimo:
  - estendere il decoder panel mutation response con `snapshot`
  - ingerire `mutation.snapshot` direttamente quando presente
  - lasciare il fallback legacy locale solo se il payload canonico manca
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift --format text`
- Commit previsto: `refactor(review-panel): ingest canonical mutation snapshots`

## Effetto osservato
- Il panel runtime usa ora lo snapshot canonico Rust quando il mutator lo restituisce.
- Il path dismiss panel-side non ricostruisce piu' localmente outcome/findings/events se il payload canonico e' disponibile.
