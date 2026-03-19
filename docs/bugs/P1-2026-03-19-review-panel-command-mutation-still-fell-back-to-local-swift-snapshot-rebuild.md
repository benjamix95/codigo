# P1 - Il panel review manteneva ancora un fallback locale sul command mutation snapshot

## Bug Fix Record
- Categoria: B
- Bug: [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift) manteneva ancora due fallback locali dopo `review_core_command_mutate_snapshot`:
  - ricostruzione locale di `dismiss`
  - ricostruzione locale da `findings/events` quando mancava `snapshot`
- Sintomo:
  - il panel aggiornava ancora findings, events e outcome in Swift nel path mutation
  - la semantica non era pienamente fail-closed quando il runtime Rust era indisponibile
- Impatto: restava logica di dominio Swift in uno dei boundary panel-side più sensibili, proprio nel path di mutazione snapshot.
- Gravita': alta, perche' tocca il bridge tra panel runtime e source of truth del dominio review.
- Steps to reproduce:
  1. Aprire [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift).
  2. Cercare `mutateSnapshotUsingRust(...)`.
  3. Verificare la presenza del fallback locale `dismiss` e della ricostruzione da `findings/events`.
- Risultato attuale: il panel manteneva ancora logica locale dopo il mutator Rust.
- Risultato atteso: il panel deve ingerire solo lo `snapshot` canonico Rust sul path di successo e fallire chiuso quando il runtime non risponde.
- Causa probabile: il callsite panel-side era rimasto compatibile con una versione precedente del dylib che non serializzava ancora `snapshot`.
- Scope consentito:
  - [CodeReviewPanelStore+SnapshotMutation.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift)
  - [CodeReviewPanelSessionScopingTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/CodeReviewPanelSessionScopingTests.swift)
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - review session registry
  - patch workflow services
  - panel chat extraction
- Moduli confinanti da verificare:
  - `CodeReviewPanelSessionScopingTests`
  - strict cutover gate review
  - il dylib usato dai test in `Native/RustCore/build/lib`
- Test da aggiungere o aggiornare:
  - regression test per `dismiss` fail-closed con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
- Strategia di fix minimo:
  - rimuovere i fallback locali in `mutateSnapshotUsingRust(...)`
  - richiedere `mutation.snapshot` come unico success path canonico
  - aggiungere un test di regressione sul fail-closed
  - riallineare il dylib test-side con `./scripts/build_rust_search_backend.sh`
- Verifica post-fix:
  - `./scripts/build_rust_search_backend.sh`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFallbackUsesRustMutationAndMarksWontFix -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelDismissFailsClosedWhenRustMutationUnavailable`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+SnapshotMutation.swift --format text`
- Commit previsto: `refactor(review-panel): require canonical command mutation snapshots`

## Effetto osservato
- Il panel mutation path accetta solo snapshot canonici prodotti dal core Rust.
- Quando il runtime Rust è disabilitato, il dismiss panel-side non muta più localmente lo snapshot.
- I test panel-side sono stabili solo se il dylib in `Native/RustCore/build/lib` è riallineato ai sorgenti correnti.
