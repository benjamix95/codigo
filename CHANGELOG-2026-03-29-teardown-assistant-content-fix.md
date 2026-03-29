# Changelog — 2026-03-29 — Fix contenuto assistente invisibile dopo turn completion

## Problema

Quando il turno dell'assistente veniva completato, il contenuto della risposta spariva dalla UI della chat. Il testo era visibile solo durante lo streaming (tramite overlay del runtime) ma scompariva al teardown. Un riavvio dell'app lo rendeva nuovamente visibile.

## Causa radice

Due gap nel percorso di teardown della pipeline:

1. **Mancato commit esplicito del `chatTurnState`**: In `runPipelineEventsCommit`, quando il boundary Rust gestisce gli eventi con successo, `ChatPipelineCommitter.commit()` non veniva chiamato. Lo store riceveva aggiornamenti tramite `sync_store_from_runtime` dentro Rust, ma il commit esplicito Swift-side (`sync_assistant_pipeline_state`) — che esegue il merge completo di blocchi, contenuto e metadati — avveniva solo nel percorso fallback Swift. Al momento del teardown, quando l'overlay di streaming veniva rimossa, lo store base poteva avere dati incompleti.

2. **Notifica SwiftUI mancante post-rimozione runtime**: Dopo la rimozione di `runtimesByConversation` e `snapshotsByConversation` in `completeTeardown`, non veniva emessa una `flushConversationChangeNotification()`. Con il throttling attivo su `conversationsDidChange()` (max 1/150ms durante `isLoading`), SwiftUI poteva non ricevere una notifica per re-renderizzare con i dati base dello store.

## Fix applicato

### File: `PipelineIntegrationService+Teardown.swift`

**Modifica 1 — `claimTeardownRuntime`:**
Aggiunto `ChatPipelineCommitter.commit(runtime.chatTurnState, chatStore: chatStore, persistImmediately: true)` dopo il flush degli eventi pending. Questo garantisce che il messaggio assistente nello store abbia testo e blocchi completi prima che l'overlay di streaming venga rimossa.

**Modifica 2 — `completeTeardown`:**
Aggiunto `chatStore?.flushConversationChangeNotification()` dopo la rimozione di runtime e snapshot. Questo forza una notifica non-throttled a SwiftUI, garantendo che la UI si aggiorni con `snapshotIsLoading = false` e i messaggi storici includano il contenuto appena committato.

## Test di regressione

### File: `PipelineIntegrationTeardownContentTests.swift`

- `testFinalizeExecutionPreservesAssistantContentInStore` — simula textDelta → turnCompleted → finalizeExecution, verifica che contenuto e blocchi sopravvivano nello store
- `testFinalizeExecutionFlushesThrottledNotification` — verifica che `objectWillChange` venga emesso dopo `completeTeardown`

## File modificati

| File | Tipo |
|------|------|
| `App/.../PipelineIntegrationService+Teardown.swift` | Fix |
| `Tests/.../PipelineIntegrationTeardownContentTests.swift` | Test regressione (nuovo) |
| `docs/bugfix-records/2026-03-29-teardown-assistant-content-invisible.md` | Documentazione bug |
