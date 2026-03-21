# P1 - La main chat crashava su `begin_task` quando il task runtime Rust non era disponibile

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: `ChatStore.beginTask(conversationId:)` passava da `requireRustTaskRuntime("begin_task")`; se il task runtime Rust restituiva `nil`, il bridge Swift andava in `assertionFailure` e il submit della main chat crashava.
- Sintomo:
  - `Enter` o `Invia` entravano davvero nel percorso di submit
  - subito dopo compariva `Fatal error: Main chat task runtime unavailable for begin_task`
  - la chat non inviava il messaggio perché l'app si fermava sul bootstrap dello stato task
- Impatto: crash sul flusso core di invio della main chat.
- Gravità: alta
- Steps to reproduce:
  1. Aprire la main chat in uno stato in cui il transport provider selezionato funziona ma il task runtime Rust non risponde.
  2. Digitare un messaggio nel composer.
  3. Premere `Return` o cliccare `Invia`.
  4. Osservare il crash nel bridge `ChatStore+RustBridge.swift` durante `begin_task`.
- Risultato attuale: il fallback Swift per lo stato task esisteva già, ma veniva usato solo in modalità test; nel runtime dell'app si arrivava invece a `assertionFailure`.
- Risultato atteso: se il task runtime Rust non è disponibile, `begin_task`, `set_task_status` ed `end_task` devono degradare sul fallback Swift senza crashare.
- Causa probabile:
  - gating eccessivo del fallback task runtime al solo ambiente di test
  - uso di `requireRustTaskRuntime(...)` in un percorso utente che deve essere resiliente
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `Tests/SoloCodeAppTests/ChatStoreTaskOwnershipTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor del task runtime Rust
  - modifiche al provider transport o al composer UI
  - redesign dei task status
- Moduli confinanti da verificare:
  - `beginTask(conversationId:)`
  - `endTask(conversationId:)`
  - `setTaskStatus(_:for:)`
- Test da aggiungere o aggiornare:
  - regressione su `beginTask` con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
  - mantenimento del contratto osservabile su `isLoading`, `activeTaskConversationId`, `taskStatusTexts`, `taskStartDates`
- Strategia di fix minimo:
  - usare il fallback task runtime Swift anche fuori dai test
  - rimpiazzare il fail-fast con log diagnostico se persino il fallback non è applicabile
- Verifica post-fix:
  - suite `ChatStoreTaskOwnershipTests` verde con scenario runtime non disponibile
  - smoke manuale consigliato: submit main chat nel caso che prima crashava
- Commit previsto: `fix(chat): fallback when rust task runtime is unavailable`
