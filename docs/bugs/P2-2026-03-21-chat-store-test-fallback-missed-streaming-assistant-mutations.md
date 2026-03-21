# Bug Fix Record
- Categoria: B
- Bug: nel ramo XCTest con bootstrap Rust differito, `ChatStore+RustBridge` non applicava localmente le mutazioni assistant-centriche di `sync_assistant_content`, `set_streaming_state` e `remove_trailing_empty_assistant_messages`.
- Sintomo: `ChatStoreStreamingTargetTests` falliva su update del messaggio assistant streaming, flip dello stato `isStreaming` e cleanup dei trailing assistant vuoti.
- Impatto: il fallback test-mode del `ChatStore` non era coerente col contratto osservabile del path Rust per i turni assistant streaming.
- Gravità: media
- Steps to reproduce:
  1. Eseguire `xcodebuild test` su `ChatStoreStreamingTargetTests`.
  2. Osservare il fallimento di `testUpdateLastAssistantMessageTargetsActiveStreamingAssistant`.
  3. Osservare il fallimento di `testSetLastAssistantStreamingTargetsActiveStreamingAssistant`.
  4. Osservare il fallimento di `testRemoveTrailingEmptyAssistantMessages`.
- Risultato attuale: le mutazioni assistant streaming venivano demandate solo al reducer Rust, assente nel ramo deferito di test.
- Risultato atteso: il fallback locale deve scegliere lo stesso assistant target e applicare il cleanup finale come nel path Rust.
- Causa probabile: il fallback XCTest iniziale copriva `addMessage` e `insertMessage`, ma non le mutazioni successive del turno assistant.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
  - `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`
- Non-scope:
  - reducer Rust dello store
  - altri mutatori non coinvolti dal failure
- Moduli confinanti da verificare:
  - `ChatStoreStreamingTargetTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test: i regression test esistevano gia' e ora devono tornare verdi
- Strategia di fix minimo:
  - aggiungere fallback locale per content sync assistant
  - aggiungere fallback locale per streaming state
  - aggiungere fallback locale per cleanup trailing assistant vuoti
- Verifica post-fix:
  - `xcodebuild test` sui casi falliti
  - rerun della suite streaming della tranche
- Commit previsto: incluso nel commit della tranche strutturale corrente
