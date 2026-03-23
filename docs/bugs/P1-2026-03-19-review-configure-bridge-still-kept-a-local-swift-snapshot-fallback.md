# P1 - Il bridge `configure` review manteneva ancora un fallback locale sullo snapshot

## Bug Fix Record
- Categoria: B
- Bug: [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift) manteneva ancora una ricostruzione locale di `config/events/outcome` nel path `configuredReviewSnapshot(...)`.
- Sintomo:
  - fallback manuale su `mutation.config` e `mutation.events`
  - ricostruzione locale di `outcome` e `lastUpdatedAt`
- Impatto: rimaneva logica review Swift in un boundary che il mutator Rust copre gia' integralmente con `snapshot`.
- Gravita': alta, perche' tocca il command loop review e la persistenza della configurazione di sessione.
- Steps to reproduce:
  1. Aprire [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift).
  2. Cercare `configuredReviewSnapshot(...)`.
  3. Verificare il fallback locale dopo `if let canonical = mutation.snapshot`.
- Risultato attuale: il bridge configurazione non era ancora completamente passivo.
- Risultato atteso: il path `configure` deve accettare solo lo snapshot canonico prodotto da Rust oppure fallire chiuso.
- Causa probabile: il callsite era stato lasciato compatibile con versioni precedenti del mutator che non serializzavano ancora sempre `snapshot`.
- Scope consentito:
  - [ReviewCommandRustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift)
  - test command-loop review gia' esistenti
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - panel runtime
  - patch workflow
  - review session Rust core
- Moduli confinanti da verificare:
  - `SoloCodeAppCodeReviewCommandLoopTests`
  - persisted snapshot configure path
  - live session configure path
- Test da aggiungere o aggiornare:
  - nessun nuovo test necessario; la suite `configure` esistente copre gia' positivo live, positivo persisted e fail-closed
- Strategia di fix minimo:
  - rimuovere il fallback locale
  - restituire solo `mutation.snapshot`
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesLiveSessionThroughCommandLoop -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandUpdatesPersistedSnapshotThroughRustMutation -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests/testConfigureCommandFailsWhenRustMutationRuntimeIsDisabled`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/CodeReview/Services/ReviewCommandRustBridge.swift --format text`
- Commit previsto: `refactor(review-command): require canonical configure snapshots`

## Effetto osservato
- Il bridge `configure` review e' ora totalmente passivo: accetta solo lo snapshot canonico Rust.
- Il path fail-closed rimane invariato quando il runtime Rust e' disabilitato.
