# P2 - Gli ultimi due file store del panel review erano ancora fuori da `Views/**`

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: gli ultimi due file Swift residui del prefisso `App/SoloCodeApp/Sources/Panels/CodeReview` erano ancora `CodeReviewPanelStore.swift` e `CodeReviewPanelStore+SnapshotMutation.swift`, pur essendo a tutti gli effetti stato/runtime edge del pannello UI.
- Sintomo: dopo i batch precedenti il backlog review-side restava a `49` file legacy non-UI, con `2` file ancora conteggiati nel prefisso panel-side.
- Impatto: il dominio review lato app non risultava ancora completamente drenato, e il contatore impediva di dichiarare il lato panel app-side chiuso.
- Gravita': media
- Steps to reproduce:
  1. Eseguire l'audit strict review-scope dopo il batch precedente.
  2. Osservare che il prefisso panel-side vale ancora `2`.
  3. Verificare che i due file residui gestiscono `ObservableObject` panel-state e mutation runtime locale.
- Risultato attuale: entrambi i file sono ora ricollocati sotto `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/`.
- Risultato atteso: il prefisso `App/SoloCodeApp/Sources/Panels/CodeReview` non deve piu' contribuire al backlog non-UI review.
- Causa probabile: la struttura iniziale del panel aveva mantenuto il main store sotto `Store/` anche dopo il progressivo spostamento del resto dei componenti su `Views/Runtime`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/*`
  - `Solo Code.xcodeproj/project.pbxproj`
- Non-scope:
  - engine `CodeReview`
  - `VerifiedFindingsCore`
  - handler MCP review
- Moduli confinanti da verificare:
  - chat state deferral
  - snapshot mutation runtime
  - panel validation/session scoping
- Test da aggiungere o aggiornare:
  - nessun test nuovo; usare regression panel gia' presenti
- Strategia di fix minimo:
  - ricollocare i due file nel subtree `Views/Runtime/`
  - aggiornare solo i path di progetto, senza cambiare simboli o contratti
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testPanelStoreRestoresCachedChatSessionState -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates -only-testing:SoloCodeAppTests/CodeReviewPanelValidationTests`
  - audit strict review-scope
- Commit previsto: `fix(review): move final panel store files under views`

## Effetto osservato
- review strict prima della tranche: `49` legacy non-UI
- review strict dopo la tranche: `47` legacy non-UI
- riduzione per prefisso:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: da `2` a `0`
