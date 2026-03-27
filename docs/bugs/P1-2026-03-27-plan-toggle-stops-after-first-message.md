# Finding: toggle Plan → prima risposta poi si ferma

- **Stato**: indagine con log NDJSON sessione Cursor `773578` → `.cursor/debug-773578.log`.
- **Ipotesi**:
  - **H1**: Screening (fase 0) imposta skip pipeline / `continueWithDirectChat` → una sola risposta “normale”, plan reset.
  - **H2**: Safety reset dopo `runMultiTurnPlanFlow` con fase ancora `.analyzing`/`.generating`, oppure `isPlanMultiTurnFlow` falso → route sbagliato.
  - **H3**: Secondo invio bloccato da “plan already in progress” (`planFlowPhase` ancora in volo).
  - **H4**: Fase 1 non passa a chiarimenti / fase 2 come previsto (`shouldRequestClarifications` falso e stop).
- **Strumentazione**: `CursorDebugSession773578Log` in send, execute turn, fase 0 skip, fase 1, safety reset.
