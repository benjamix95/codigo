# P1 — `stream_replace_text` poteva sovrascrivere il runtime text con payload divergenti

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: `sync_runtime_text_from_replace_intent()` accettava qualunque payload `stream_replace_text` non vuoto e riscriveva `runtime_snapshot.turn_state.text_by_stream_id["main"]` anche quando il runtime possedeva gia' un testo piu' aggiornato e il payload entrante era divergente.
- Sintomo: il test Rust `main_chat::ui_tests::ui_intent_stream_replace_text_syncs_runtime_text_into_store_snapshot` falliva; lo store finiva con `ignored because runtime owns the latest text` invece del testo runtime corretto `Hello world`.
- Impatto: il sync UI/runtime della chat poteva mostrare testo assistant stale o errato durante lo streaming, degradando un flusso core.
- Gravita': P1
- Steps to reproduce:
  1. Preparare uno `MainChatUiState` con `runtime_snapshot.turn_state.text_by_stream_id["main"] = "Hello world"` e store snapshot fermo a `"Hello"`.
  2. Inviare l'intent `stream_replace_text` con `text = "ignored because runtime owns the latest text"`.
  3. Osservare il contenuto finale nello store snapshot dopo `sync_store_from_runtime`.
- Risultato attuale: il runtime veniva riscritto con il payload divergente e lo store snapshot recepiva il testo sbagliato.
- Risultato atteso: se il runtime ha gia' un testo non vuoto e il nuovo payload non ne estende il prefisso corrente, l'intent deve lasciare invariato il runtime e sincronizzare lo store dal testo gia' posseduto dal runtime.
- Causa probabile: `sync_runtime_text_from_replace_intent()` trattava il payload dell'intent come source of truth assoluta senza verificare se fosse coerente con il testo corrente del runtime.
- Scope consentito: `Native/RustCore/src/main_chat/ui_state_sync.rs` e test Rust confinanti in `Native/RustCore/src/main_chat/ui_tests.rs`.
- Non-scope: reducer pipeline, store mutations non collegate, bridge Swift di altre feature.
- Moduli confinanti da verificare: `handle_ui_intent` per `stream_replace_text`, `sync_store_from_runtime`, test boundary app-side `RustMainChatUIBoundaryTests`.
- Test da aggiungere o aggiornare:
  - `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_syncs_runtime_text_into_store_snapshot -- --test-threads=1`
  - `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_preserves_interleaved_runtime_segments -- --test-threads=1`
  - `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_does_not_overwrite_previous_assistant_when_runtime_target_is_stale -- --test-threads=1`
  - `xcodebuildmcp macos test` mirato su `SoloCodeAppTests/RustMainChatUIBoundaryTests` e `SoloCodeAppTests/MainChatUIIntentRuntimeSyncTests`
- Strategia di fix minimo: introdurre una guardia che ignori i payload `stream_replace_text` divergenti quando il runtime possiede gia' un `primary_text` non vuoto; consentire comunque gli update che estendono il prefisso corrente.
- Verifica post-fix:
  1. Test Rust mirati del flusso `stream_replace_text` verdi.
  2. `cargo test --workspace -- --test-threads=1` verde in `Native`.
  3. `xcodebuildmcp macos test` mirato verde sui boundary app-side.
- Commit previsto: `fix(main-chat): ignore divergent stream replace payloads when runtime is ahead`
