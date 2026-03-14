# P1 - Il loader history review referenziava ancora il query service rimosso

## Bug Fix Record
- Categoria: A
- Bug: `ReviewPanelHistoricalFindingsLoader` in `CodeReviewPanelStore+History.swift` chiamava ancora `HistoricalFindingsQueryService.list(query:)`, simbolo gia' rimosso.
- Sintomo: il target `Solo Code-Debug` falliva a compile-time/runtime quando il panel history veniva caricato o i test app-side costruivano il target.
- Impatto: la build app-side del dominio review non era affidabile dopo il drenaggio del query service storico.
- Gravità: P1
- Steps to reproduce:
  1. Eseguire `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`.
  2. Osservare il riferimento residuo a `HistoricalFindingsQueryService`.
  3. Verificare che `VerifiedFindingsQueryService.listHistoricalFindings(query:)` sia il nuovo entrypoint corretto.
- Risultato attuale: il loader history continuava a puntare a un simbolo rimosso.
- Risultato atteso: il loader deve usare `VerifiedFindingsQueryService.listHistoricalFindings(query:)`.
- Causa probabile: la tranche che aveva fuso il query service storico non aveva drenato il call site app-side del panel history.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Models`
  - `Tests/SoloCodeAppTests`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - runtime Rust
  - engine verified findings
  - UI rendering non coinvolta nel loader
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTests`
  - `ReviewPanelFindingsHistoryLiveBoardTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; riuso dei test panel history gia' esistenti
- Strategia di fix minimo:
  - sostituire il call site con il nuovo entrypoint
  - ridurre contestualmente di una unita' il backlog panel review assorbendo il modello residuale `ReviewPanelChatPresentationModels.swift`
- Verifica post-fix:
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatModels.swift,App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelChatPresentationModels.swift,"Solo Code.xcodeproj/project.pbxproj" --format text`
  - `xcodebuild build-for-testing -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  - `./scripts/bootstrap_test_bundles.sh`
  - `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsLoadsDeferredSnapshotFromLoader -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testRefreshHistoricalFindingsReadsPersistedWorkspaceHistory`
- Commit previsto: `fix(review): restore historical findings loader and fold chat presentation model`

## Fix applicato
- `ReviewPanelHistoricalFindingsLoader.fetch` ora usa `VerifiedFindingsQueryService.listHistoricalFindings(query:)`
- `ReviewPanelChatPresentationModels.swift` e' stato assorbito in `ReviewPanelChatModels.swift`
- rimosso il file residuale dal progetto Xcode

## Esito
- la build app-side del panel history torna valida sul path del loader
- il prefix hard-fail `App/SoloCodeApp/Sources/Panels/CodeReview` scende di una unita' nel backlog Swift legacy
