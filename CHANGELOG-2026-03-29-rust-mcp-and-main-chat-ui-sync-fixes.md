# Changelog — Rust MCP build blocker + main chat UI/runtime sync

## Scope
- Ripristino del build/test del crate `coderide_mcp_server_rust`.
- Correzione della sincronizzazione `stream_replace_text` nel runtime Rust di main chat.

## Modifiche
- Ripristinate in `Native/CoderideMCPServerRust/src/debug_tools.rs` le stringhe generate per marker e instrumentation di debug, i pattern di cleanup e gli alias supportati per `debug_clean`.
- Estratti i test dei debug tools in `Native/CoderideMCPServerRust/src/debug_tools/generated_tests.rs` per tenere il delta di regressione isolato e leggibile.
- Introdotti `supports()` senza side effect nei dispatcher Rust MCP (`audit_tools`, `benchmark_tools`, `debug_tools`, `diagnostics_tools`, `edit_tools`, `review_tools`, `skill_tools`, `web_tools`) e usati in `handlers.rs` per evitare che il test di routing eseguisse tool reali e si bloccasse.
- Aggiunta in `Native/RustCore/src/main_chat/ui_state_sync.rs` una guardia che ignora payload `stream_replace_text` divergenti quando il runtime possiede gia' il testo piu' aggiornato, preservando invece i casi che estendono il prefisso corrente.

## Bug documentati
- Build blocker MCP Rust gia' registrato in `docs/bugs/P0-2026-03-29-rust-debug-tools-build-blocker.md`.
- Nuovo record: `docs/bugs/P1-2026-03-29-main-chat-ui-stream-replace-divergence.md`.

## Verifica
- `cargo test -p coderide_mcp_server_rust -- --test-threads=1`
- `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_syncs_runtime_text_into_store_snapshot -- --test-threads=1`
- `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_preserves_interleaved_runtime_segments -- --test-threads=1`
- `cargo test -p solocode_rust_core main_chat::ui_tests::ui_intent_stream_replace_text_does_not_overwrite_previous_assistant_when_runtime_target_is_stale -- --test-threads=1`
- `cargo test --workspace -- --test-threads=1`
- `xcodebuildmcp macos test` mirato su `SoloCodeAppTests/RustMainChatUIBoundaryTests` e `SoloCodeAppTests/MainChatUIIntentRuntimeSyncTests` -> 8/8 passati
