# Bug / finding: chat Claude si ferma subito

- **Stato**: indagine con log runtime (sessione agent `773578`).
- **Sintomo**: invio messaggio con Claude → risposta/flusso termina immediatamente.
- **Ipotesi (da verificare con NDJSON)**:
  - **H1**: il poll Rust (`chat_core_runtime_poll_provider`) restituisce subito `isTerminal` o evento `completed` senza (o con poco) testo.
  - **H2**: `chat_core_provider_start_session` fallisce o rifiuta la sessione (errore in avvio).
  - **H3**: non viene usato il percorso `standardStream` / transport Rust atteso (es. route `agentPipeline` o plan).
  - **H4**: lo stream termina con stringa finale vuota lato Swift post-`continueIfPrematureStub`.
  - **H5**: eccezione immediata nel `Task` di send (catch con `interrupted` o errore provider).
- **Strumentazione**: `AgentDebugIngestLog` → `.cursor/debug-773578.log` (NDJSON).
- **Prossimo passo**: riproduzione utente; analisi log; fix solo con evidenza.
