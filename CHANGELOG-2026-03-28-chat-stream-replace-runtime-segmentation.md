# Changelog - 2026-03-28 - Chat stream replace runtime segmentation

- Corretto `stream_replace_text` nel layer UI Rust: ora aggiorna anche i segmenti testuali del `turnState` runtime, non solo lo snapshot store.
- Se il turno contiene già marker tool, il testo full snapshot viene riallineato al segmento testuale corrente o crea un nuovo segmento dopo l'ultimo tool.
- In questo modo il path live conserva l'interleave `text/tool/text` invece di ricadere in un solo blocco testuale con tool a valle.
- Aggiunto test Rust dedicato sul path `stream_replace_text` con timeline interleavata.
- File toccati:
  - `Native/RustCore/src/main_chat/ui_state_sync.rs`
  - `Native/RustCore/src/main_chat/ui_intents.rs`
  - `Native/RustCore/src/main_chat/ui_tests.rs`
