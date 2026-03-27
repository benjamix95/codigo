# Bug Fix Record — 2026-03-27 — Chat UI sparisce dopo il secondo messaggio

- Categoria: A — Critico
- Bug: la timeline della chat può sparire o restare visivamente vuota dopo il secondo messaggio finché non arriva un nuovo invalidation pass o un resize finestra.
- Sintomo: dopo l’invio del secondo prompt la sezione messaggi può svuotarsi temporaneamente; il contenuto ricompare da solo più tardi oppure solo dopo resize.
- Impatto: degrado severo del flusso chat core; l’utente percepisce perdita o blocco dei messaggi.
- Gravità: alta
- Steps to reproduce:
  1. Aprire una conversazione nuova.
  2. Inviare un primo messaggio e attendere risposta completa.
  3. Inviare un secondo messaggio.
  4. Durante/fine stream osservare la sezione messaggi.
- Risultato attuale: in alcuni casi `messagesConversationSnapshot` resta stale oppure viene sostituito da uno snapshot vuoto transiente; la UI non si riallinea subito e il contenuto sembra sparire.
- Risultato atteso: la timeline deve restare visibile e riallinearsi immediatamente a ogni publish rilevante del `ChatStore`, senza dipendere da resize o invalidazioni esterne.
- Causa probabile:
  - la view ha ridotto le dipendenze dirette da `chatStore.conversations`, ma mancava un hook esplicito su `chatStore.objectWillChange` per riallineare `messagesConversationSnapshot`;
  - inoltre uno store vuoto transiente subito dopo la fine del task poteva sostituire uno snapshot non vuoto dello stesso thread;
  - (fix 2) durante pipeline streaming, `chatStore.objectWillChange` è throttlato a 150ms ma `pipelineIntegrationService` pubblica ogni ~32ms — mancava un hook su `pipelineIntegrationService.objectWillChange` per lo snapshot refresh;
  - (fix 2) `shouldPreserveSnapshotAgainstTransientEmptyStore` proteggeva solo contro `freshMessageCount == 0`, non contro riduzione parziale dei messaggi (es. Rust ritorna 2 messaggi quando lo snapshot ne ha 4).
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift`
  - `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridgeMessages.swift`
  - test dedicati in `Tests/SoloCodeAppTests`
- Non-scope:
  - refactor architetturali del renderer chat
  - cambiamenti al reducer Rust o al layout root non necessari al fix
  - ottimizzazioni non correlate
- Moduli confinanti da verificare:
  - bridge `ChatStore` / runtime task
  - refresh snapshot chat
  - teardown fine stream
- Test da aggiungere o aggiornare:
  - test della policy che preserva snapshot non vuoti contro store empty transienti
  - test del flush immediato delle notifiche conversazione in coda durante streaming
- Strategia di fix minimo:
  - riallineare lo snapshot su `chatStore.objectWillChange`;
  - introdurre una breve grace window post-busy per ignorare empty store transienti dello stesso thread;
  - forzare flush notifiche conversazione alla chiusura task.
- Verifica post-fix:
  - suite test mirata su `SoloCodeAppTests`
  - review dei file toccati
- Commit previsto:
  - `fix(chat): prevent chat timeline disappearing after second message`
