# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: fix applicato; verifica post-fix con NDJSON consigliata.
- **Evidenza (NDJSON `773578`)**:
  - `runMultiTurnPlanFlow_returned`: `outcome=completed`, `planPhase=analyzing`, `planningState=idle`.
  - Subito dopo: `reset_stuck_analyzing_or_generating` (`phase=analyzing`).
  - Assenza di `phase1_after_analysis` in ~120ms → uscita anticipata (tipicamente **prompt di fase vuoto** prima della prima `runStream` lunga di analisi).
- **Ipotesi valutate**:
  - **H1** (screening skip → direct chat): **RESPINTA** per questa run (nessun `screening_skip_full_pipeline`).
  - **H2** (safety reset su fase bloccata): **CONFERMATA** come sintomo; la causa era il prefight abort senza reset UI sulla stessa conversazione.
  - **H3/H4**: **NON applicabili** a questa run (nessun secondo invio / fase 1 non raggiunta).
- **Causa root**: `cleanupPlanFlowAfterConversationSwitch` azzera la fase solo se `targetConversationId != conversationId`. Con lo stesso thread, guard su prompt vuoto chiamava solo quello → nessun reset → `planFlowPhase` restava `.analyzing` con outcome `completed`.
- **Fix**: `resetPlanFlowAfterAbortedPreflight` sui guard `prompt.isEmpty` (fasi 0–3).
- **Strumentazione**: `CursorDebugSession773578Log` — rimuovere dopo conferma utente post-fix.
