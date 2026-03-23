# 2026-03-09 — Review command versioned VerifiedFindings

## Obiettivo
Rendere effettivo il guard di versione del core `VerifiedFindings` anche nei workflow review dell'app, senza introdurre nuove state machine o logica duplicata.

## Modifiche
- `VerifiedFindingsSessionSyncService` ora:
  - conserva la `version` dei finding già presenti
  - incrementa la `version` quando il contenuto di dominio del finding cambia
- `SoloCodeApp+CodeReviewCommandMutations` ora:
  - costruisce `VerifiedCommandMeta` con `expectedEntityVersion`
  - risolve la versione corrente del finding dal backend shared
- `SoloCodeApp+CodeReviewPatchCommands` passa la versione attesa anche ai comandi patch/revalidate/apply
- aggiunto test di regressione per il versioning del sync service

## File toccati
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService.swift`
- `Engine/CoderEngine/Sources/VerifiedFindingsCore/Application/VerifiedFindingsSessionSyncService+Mappings.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommandMutations.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview/SoloCodeApp+CodeReviewPatchCommands.swift`
- `Tests/CoderEngineTests/VerifiedFindings/VerifiedFindingsSessionSyncServiceTests.swift`

## Validazione
Eseguita:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/VerifiedFindingsSessionSyncServiceTests \
  -only-testing:SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests
```

Esito:
- 4 test eseguiti
- 0 failure

## Note
Il warning su `mutateReviewSnapshot` in contesto sync non è stato modificato in questo tranche. Il comportamento introdotto qui è confinato al versioning e al passaggio del metadata di concorrenza.
