# P2 - I test del live board storico review restano fragili dopo il fix del loader

## Bug Fix Record
- Categoria: B
- Bug: `ReviewPanelFindingsHistoryLiveBoardTests` continua a fallire su aspettative `currentHistoricalLiveRunState` non nulle, anche dopo la correzione del loader history.
- Sintomo: i test `testCurrentHistoricalLiveRunStateBuildsRealtimeFileBoardFromWorkerPlans`, `...RemainsVisibleAsCompletedSummary` e `...UsesSnapshotFileLedgerWhenAvailable` restituiscono `nil` al posto del live state atteso.
- Impatto: il perimetro app-side history/live board non e' ancora completamente stabile; i test non possono essere usati come gate per tranche non mirate su quel flow senza una diagnosi dedicata.
- Gravità: P2
- Steps to reproduce:
  1. Eseguire `xcodebuild test-without-building -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`.
  2. Osservare i failure su `currentHistoricalLiveRunState`.
- Risultato attuale: il live board storico risulta `nil` nei test che lo esercitano.
- Risultato atteso: il live state deve essere costruito da worker plans o file ledger quando presenti.
- Causa probabile: ownership del live board ancora fragile tra snapshot history, swarm cards e derivazione UI.
- Scope consentito per il futuro fix:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+History.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests.swift`
- Non-scope:
  - query history persistence
  - MCP handler
  - pipeline engine
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTests`
  - `ReviewPanelFindingsHistoryRustFallbackTests`
- Test da aggiungere o aggiornare:
  - diagnosi e regression sul flow `currentHistoricalLiveRunState`
- Strategia di fix minimo:
  - non inclusa in questa tranche; bug registrato per analisi dedicata
- Verifica post-fix:
  - da definire nella tranche dedicata
- Commit previsto: n/a
