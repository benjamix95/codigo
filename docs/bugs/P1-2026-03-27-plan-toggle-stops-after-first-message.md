# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: risolto e verificato con NDJSON sessione `773578`.
- **Evidenza pre-fix**: `runMultiTurnPlanFlow_returned` con `planPhase=analyzing` + `reset_stuck_analyzing_or_generating`; nessuna `phase1_after_analysis` in ~120 ms (prefight con prompt vuoto).
- **Causa root**: `cleanupPlanFlowAfterConversationSwitch` non resetta sulla **stessa** conversazione; prompt plan vuoti (`generatedPrompt` assente dal runtime) lasciavano la fase incollata a `.analyzing`.
- **Fix**: `resetPlanFlowAfterAbortedPreflight` sui guard `prompt.isEmpty` (fasi 0–3).
- **Evidenza post-fix**: `runMultiTurnPlanFlow_returned` con `outcome=completed`, `planPhase=idle`, `planningState=idle` (niente safety reset).
- **Strumentazione sessione 773578**: rimossa dal codice.
