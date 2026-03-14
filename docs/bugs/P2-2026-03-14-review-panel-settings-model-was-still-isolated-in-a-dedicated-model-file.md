# P2 - Il panel settings model restava isolato in un file modello dedicato

## Bug Fix Record
- Categoria: B
- Bug: `ReviewPanelSettingsModel.swift` restava un file Swift non-UI separato pur contenendo solo settings, custom command e persistence helpers del panel review.
- Sintomo: il prefisso `App/SoloCodeApp/Sources/Panels/CodeReview` manteneva un file residuale di soli modelli/settings.
- Impatto: backlog Swift non-UI più alto nel panel review e frammentazione dei modelli del panel.
- Gravità: P2
- Steps to reproduce:
  1. Ispezionare `App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelSettingsModel.swift`.
  2. Verificare che il file contenga solo `ReviewPanelSettings`, enum delivery/conflict, `ReviewPanelCustomCommand` e persistence.
  3. Notare che il file compare ancora nel backlog hard-fail del panel review.
- Risultato attuale: i settings del panel vivevano in un file modello dedicato.
- Risultato atteso: i settings del panel devono stare nei file modello già esistenti del panel review, senza file residuale separato.
- Causa probabile: tranche precedenti avevano drenato wrapper review più urgenti lasciando questo file solo-modelli isolato.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Models`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `Tests/SoloCodeAppTests`
- Non-scope:
  - store logic
  - engine review
  - runtime Rust
- Moduli confinanti da verificare:
  - `CodeReviewPanelValidationTests`
  - build `Solo Code-Debug`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso della suite validation panel
- Strategia di fix minimo:
  - spostare `ReviewPanelSettings`, `ReviewPatchDeliveryMode` e `ReviewConflictAutomation` in `CodeReviewPanelModels.swift`
  - spostare `ReviewPanelCustomCommand` e `ReviewPanelSettingsPersistence` in `ReviewPanelChatModels.swift`
  - rimuovere il file e i riferimenti Xcode
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Models/CodeReviewPanelModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelSettingsModel.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`
- Commit previsto: `refactor(review): fold panel settings model into panel models`

## Fix applicato
- `ReviewPanelSettings`, `ReviewPatchDeliveryMode` e `ReviewConflictAutomation` spostati in `CodeReviewPanelModels.swift`
- `ReviewPanelCustomCommand` e `ReviewPanelSettingsPersistence` spostati in `ReviewPanelChatModels.swift`
- rimosso `ReviewPanelSettingsModel.swift` dal filesystem e dal progetto Xcode

## Esito
- il prefisso panel review riduce di un'altra unita' il backlog Swift legacy non-UI
- nessun cambiamento comportamentale previsto
