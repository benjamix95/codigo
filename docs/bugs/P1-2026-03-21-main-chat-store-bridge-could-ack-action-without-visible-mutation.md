# P1 - Il bridge store della main chat poteva accettare l'azione senza lasciare una mutazione visibile

## Bug Fix Record
- Priorità: P1
- Categoria: A - Critico
- Bug: nel percorso main chat, alcune azioni store-side (`append_message`, `sync_assistant_content`, `set_streaming_state`, `insert_message_before`) potevano risultare accettate dal boundary Swift/Rust senza produrre la mutazione osservabile nella conversazione corrente; l'invio partiva ma la timeline restava vuota.
- Sintomo:
  - il log mostrava submit riuscito e provider/CLI in esecuzione
  - non comparivano né il messaggio utente né il placeholder assistant
  - il task bar si aggiornava, ma l'area messaggi restava nera/vuota
- Impatto: la chat sembrava ferma anche quando il backend stava lavorando correttamente.
- Gravità: alta
- Steps to reproduce:
  1. Inviare un turno main chat in modalità `Agent`.
  2. Lasciare il bridge store Rust in uno stato non affidabile o disallineato.
  3. Verificare che `sendMessage` parta e il processo CLI produca output.
  4. Osservare che la conversazione visibile non mostra messaggi.
- Risultato attuale: il fallback locale scattava solo quando l'azione Rust falliva esplicitamente; se il boundary restituiva uno stato senza la mutazione attesa, la UI restava vuota.
- Risultato atteso: dopo ogni mutazione critica il `ChatStore` deve verificare che l'effetto sia visibile; se manca, deve applicare una correzione locale minima.
- Causa probabile:
  - mancava una verifica post-azione del contratto osservabile sulla conversazione
  - il boundary Rust poteva lasciare snapshot stale o no-op dal punto di vista UI
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - refactor del projection/runtime pipeline
  - modifiche al composer o al provider transport
  - redesign della timeline
- Moduli confinanti da verificare:
  - `addMessage`
  - `updateLastAssistantMessage`
  - `setLastAssistantStreaming`
  - `insertMessage`
- Test da aggiungere o aggiornare:
  - fallback su `addMessage` con bridge disabilitato
  - fallback su `updateLastAssistantMessage` con bridge disabilitato
  - mantenimento dei test di streaming target e task ownership
- Strategia di fix minimo:
  - provare prima l'azione Rust
  - verificare che la mutazione sia realmente osservabile nella conversazione
  - in caso contrario, applicare una mutazione locale di recupero
- Verifica post-fix:
  - `ChatStoreStreamingTargetTests` verdi
  - `ChatStoreTaskOwnershipTests` verdi
  - smoke manuale consigliato: submit `Agent` con timeline che mostra subito messaggio utente e assistant
- Commit previsto: `fix(chat): verify store mutations when rust bridge is stale`
