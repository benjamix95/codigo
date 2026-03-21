# Bug Fix Record
- Categoria: B
- Bug: nel ramo XCTest con bootstrap Rust differito, `ChatStore+RustBridge` applicava il fallback locale di `addMessage` senza aggiornare il titolo della nuova conversazione dal primo messaggio utente, e `insertMessage(before:)` non aveva alcun fallback locale.
- Sintomo: `ChatStoreStreamingTargetTests` falliva su titolo rimasto `New conversation`, inserimento mancato prima dell'anchor, e uno dei casi andava in crash per accesso fuori indice.
- Impatto: regressione del contratto base dello store chat in ambiente test quando il core Rust e' deferito.
- Gravità: media
- Steps to reproduce:
  1. Eseguire `xcodebuild test` su `ChatStoreStreamingTargetTests`.
  2. Osservare il fallimento di `testAddMessageUpdatesNewConversationTitleFromFirstUserMessage`.
  3. Osservare il fallimento/crash di `testInsertMessagePlacesEntryBeforeAnchorMessage`.
- Risultato attuale: il fallback XCTest non era isomorfo al comportamento del reducer Rust.
- Risultato atteso: in test il fallback locale deve mantenere titolo thread e inserimento prima dell'anchor come nel path Rust.
- Causa probabile: fallback introdotto solo per append semplice, senza coprire i side effect di titolo thread e insert-before.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`
- Non-scope:
  - reducer Rust dello store
  - altri mutatori `ChatStore` non coinvolti dal failure
- Moduli confinanti da verificare:
  - `ChatStoreStreamingTargetTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: i regression test esistevano gia' e ora devono tornare verdi
- Strategia di fix minimo:
  - aggiornare il fallback locale di `addMessage`
  - aggiungere il fallback locale di `insertMessage(before:)`
- Verifica post-fix:
  - `xcodebuild test` sui casi falliti
  - rerun della suite streaming della tranche
- Commit previsto: incluso nel commit della tranche strutturale corrente
