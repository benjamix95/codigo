# P1 - La main chat poteva inviare davvero ma non mostrare alcun messaggio quando il bridge store Rust era disabilitato

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: dopo un submit riuscito della main chat, `append_message` e `sync_assistant_content` potevano fallire in silenzio quando `ReviewCoreBridge` era disabilitato; il processo CLI partiva, ma la conversazione visibile restava vuota.
- Sintomo:
  - il log mostrava `sendMessage SUCCESS` e output del provider
  - non appariva il messaggio utente
  - non appariva il placeholder assistant o la risposta streaming
- Impatto: la chat sembrava non inviare nulla anche se il runtime backend stava già eseguendo il turno.
- Gravità: alta
- Steps to reproduce:
  1. Avviare la main chat con `ReviewCoreBridge` disabilitato o non disponibile.
  2. Inviare un messaggio dal composer.
  3. Osservare nei log che `sendMessage` e il provider partono davvero.
  4. Verificare che la timeline della chat non mostri né il messaggio utente né la risposta assistant.
- Risultato attuale: i metodi store-side come `addMessage` e `updateLastAssistantMessage` usavano il fallback locale solo in modalità test; nel runtime normale il fallimento del bridge Rust lasciava la chat senza mutazioni visibili.
- Risultato atteso: se il bridge store Rust non risponde, il `ChatStore` deve applicare comunque le mutazioni principali sulla snapshot locale della conversazione.
- Causa probabile:
  - fallback locale limitato al solo ambiente di test
  - assenza di degradazione app-side per `append_message`, `sync_assistant_content`, `set_streaming_state`, `insert_message_before`
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor completo dello store Rust
  - modifiche ai provider o al composer
  - redesign della timeline chat
- Moduli confinanti da verificare:
  - `addMessage`
  - `updateLastAssistantMessage`
  - `setLastAssistantStreaming`
  - `insertMessage`
- Test da aggiungere o aggiornare:
  - regressione su `addMessage` con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
  - regressione su `updateLastAssistantMessage` con bridge Rust disabilitato
- Strategia di fix minimo:
  - tentare prima l'azione Rust
  - se fallisce, applicare la mutazione minima necessaria sulla conversazione locale
  - persistere subito con i meccanismi già esistenti
- Verifica post-fix:
  - `ChatStoreStreamingTargetTests` e `ChatStoreTaskOwnershipTests` verdi
  - smoke manuale consigliato: submit con `ReviewCoreBridge disabled`, visibilità immediata di messaggio utente e assistant
- Commit previsto: `fix(chat): fallback message mutations when rust store bridge is unavailable`
