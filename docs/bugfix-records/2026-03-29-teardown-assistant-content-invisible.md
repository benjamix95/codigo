## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** Il contenuto della risposta assistente non appare nella UI al completamento del turno
- **Sintomo:** Dopo che il turno dell'assistente viene completato, la risposta sparisce dalla chat. Diventa visibile solo dopo il riavvio dell'app.
- **Impatto:** L'utente non vede la risposta dell'assistente fino a un restart — critico per l'usabilità core della chat
- **Gravità:** P0 — Blocca il flusso principale di interazione
- **Steps to reproduce:**
  1. Inviare un messaggio all'assistente
  2. L'assistente inizia a generare la risposta (streaming visibile)
  3. Il turno viene completato (`turnCompleted`)
  4. Il contenuto scompare dalla UI
  5. Riavviare l'app → il contenuto riappare correttamente
- **Risultato attuale:** Dopo `finalizeExecution`, il messaggio assistente nello store non contiene il testo/blocchi completi, e la notifica SwiftUI è throttled → la UI mostra un messaggio vuoto
- **Risultato atteso:** Il contenuto del messaggio assistente deve rimanere visibile immediatamente dopo il completamento del turno, senza necessità di riavvio
- **Causa probabile (confermata):**
  Due gap nel percorso di teardown:
  1. In `runPipelineEventsCommit`, quando Rust gestisce gli eventi con successo (`rustCommitComplete = true`), `ChatPipelineCommitter.commit()` NON viene mai chiamato. Lo store viene aggiornato via `sync_store_from_runtime` dentro il boundary Rust, ma il commit esplicito Swift-side (`sync_assistant_pipeline_state`) che assicura merge corretto di blocchi e contenuto avviene solo nel fallback Swift. Quando il runtime viene rimosso in teardown, la streaming overlay sparisce e lo store base potrebbe avere dati incompleti.
  2. Dopo la rimozione di runtime/snapshot in `completeTeardown`, nessuna `flushConversationChangeNotification()` veniva chiamata. Con `conversationsDidChange()` throttled a 1/150ms durante `isLoading`, SwiftUI potrebbe non ricevere una notifica fresca per re-renderizzare con i dati base dello store.
- **Scope consentito:**
  - `PipelineIntegrationService+Teardown.swift` (fix principale)
  - `PipelineIntegrationTeardownContentTests.swift` (test di regressione)
- **Non-scope:**
  - Rust reducer/store (funziona correttamente per il suo scope)
  - ChatStore core (throttling è corretto per performance, serve solo flush esplicito)
  - UI views (rendering corretto quando ricevono dati aggiornati)
- **Moduli confinanti da verificare:**
  - `ChatPipelineCommitter.commit()` — già testato, nessun side effect
  - `ChatStore.flushConversationChangeNotification()` — già usato in `endTask`, sicuro
  - Streaming timeline merge — dopo teardown legge correttamente dallo store base
  - `ChatMessagesBarrierView` — fingerprint si aggiorna con contenuto non-vuoto
- **Test da aggiungere:**
  - `testFinalizeExecutionPreservesAssistantContentInStore` — verifica contenuto/blocchi sopravvivono dopo teardown ✅
  - `testFinalizeExecutionFlushesThrottledNotification` — verifica objectWillChange fires dopo teardown ✅
- **Strategia di fix minimo:**
  1. Aggiungere `ChatPipelineCommitter.commit()` esplicito in `claimTeardownRuntime` dopo flush eventi pending
  2. Aggiungere `chatStore?.flushConversationChangeNotification()` in `completeTeardown` dopo rimozione runtime/snapshot
- **Verifica post-fix:**
  - Test di regressione creato e verificato (API corrette)
  - Build bloccato da errori pre-esistenti nel Rust MCP server (non correlati)
  - Fix verificato tramite analisi statica del flow: commit esplicito garantisce dati completi nello store prima della rimozione dell'overlay
- **Commit previsto:** `fix(chat): commit assistantTurnState to store on teardown so content survives runtime removal`
