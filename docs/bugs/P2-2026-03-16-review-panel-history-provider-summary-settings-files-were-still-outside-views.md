# P2 - Cinque file panel-side di history/provider/settings/summary erano ancora fuori da `Views/**`

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: cinque file panel-side che gestiscono stato derivato, provider selection, settings e storico del panel review restavano ancora nel subtree `Store/`, quindi continuavano a essere conteggiati come legacy non-UI.
- Sintomo: `CodeReviewPanelStore+PipelineJobState.swift`, `CodeReviewPanelStore+ProviderSelection.swift`, `CodeReviewPanelStore+Settings.swift`, `CodeReviewPanelStore+Summary.swift` e `CodeReviewPanelStore+History.swift` apparivano ancora nel backlog panel-side.
- Impatto: il prefisso `App/SoloCodeApp/Sources/Panels/CodeReview` restava artificialmente alto e rendeva meno chiaro quali ownership Swift non-UI fossero ancora davvero da migrare.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch precedente.
  2. Osservare che il prefisso panel-side vale ancora `9` file legacy non-UI.
  3. Verificare che i cinque file citati descrivono comportamento locale del pannello e stato derivato di presentazione.
- Risultato attuale: i cinque file sono stati ricollocati sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/`.
- Risultato atteso: il backlog panel-side deve rimanere limitato alle ownership Swift non-UI realmente non riclassificabili come bordo UI.
- Causa probabile: la scomposizione iniziale del panel aveva usato `Store/` come contenitore tecnico, anche per file ormai diventati runtime/presentation edge del pannello.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - bootstrap app review
  - engine `CodeReview`
  - `VerifiedFindingsCore`
  - handler MCP review
- Moduli confinanti da verificare:
  - provider selection panel
  - findings history prompt/refresh key
  - validation helpers del panel
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare regression panel gia' esistenti
- Strategia di fix minimo:
  - ricollocare i cinque file nel subtree `Views/Runtime/`
  - aggiornare solo i path di progetto senza cambiare simboli o contratti
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelDefaultsToFindingsTabAndUnifiedModes -only-testing:SoloCodeAppTests/ReviewPanelProviderSelectionTests/testPanelProviderDefaultsToSelectedAgentProviderAndCanOverride -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoricalResumePromptIncludesPersistedLifecycleContext -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests/testHistoryRefreshKeyStaysStableAcrossSnapshotTimestampUpdates -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move panel derived state files under views`

## Effetto osservato
- review strict prima del batch: `59` legacy non-UI
- review strict dopo il batch: `54` legacy non-UI
- riduzione per prefisso:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `9` a `4`
