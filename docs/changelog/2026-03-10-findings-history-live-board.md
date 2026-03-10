# 2026-03-10 — Live Review Board nel tab Findings History

## Cosa cambia
- `Findings History` non è più solo archivio persistito
- durante una review attiva mostra un `Live Review Board` enterprise-grade con:
  - progress/gate card della pipeline corrente
  - elenco file in analisi in tempo reale, deduplicato per file
  - worker/tools board con stato `running/completed/failed`
- a review conclusa il board non sparisce: resta come `Completed Run Summary` sopra l’archive storico

## Dettagli tecnici
- il live board riusa solo telemetria reale già presente:
  - `currentPipelineJobState`
  - worker plan `review-worker-plan`
  - `files_raw`
  - swarm cards pending+live
- il panel store ora reagisce ai cambi del `TaskActivityStore`, così il tab history si aggiorna davvero mentre il run è aperto
- il board live usa anche `pendingActivities`, quindi non aspetta solo il flush finale per vedere i file assegnati

## File principali
- `App/SoloCodeApp/Sources/Panels/CodeReview/Models/ReviewPanelFindingsHistoryModels.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+HistoryLive.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelFindingsHistoryTab.swift`
- `App/SoloCodeApp/Sources/Panels/CodeReview/Views/History/ReviewPanelHistoricalLiveBoard.swift`
- `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift`

## Test
- `SoloCodeAppTests/ReviewPanelFindingsHistoryTests`
- `SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
- `SoloCodeAppTests/ReviewPanelProviderSelectionTests`
