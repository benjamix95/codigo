# P1 — 2026-03-23 — Main chat timeline overwritten by partial pipeline snapshots

## Bug Fix Record
- Categoria: A — Critico
- Bug: la timeline della chat perdeva thinking, tool/context blocks e altri dati gia' persistiti quando arrivava un update pipeline parziale per lo stesso assistant message.
- Sintomo: durante o dopo lo stream l'assistant message conservava solo l'ultimo snapshot ricevuto; blocchi precedenti della timeline venivano rimpiazzati.
- Impatto: tool trace contestuale, thinking persistito e altre parti della risposta potevano sparire dalla timeline storica del messaggio.
- Gravita': alta
- Steps to reproduce:
  1. creare un assistant message con `primaryText`, `reasoning` e almeno un block operativo gia' persistito
  2. applicare `sync_assistant_pipeline_state` con uno snapshot parziale che contiene solo uno status block o altri dati incompleti
  3. osservare il messaggio persistito risultante
- Risultato attuale: i campi mancanti nello snapshot in ingresso venivano trattati come assenti e la timeline del messaggio perdeva blocchi e contesto precedenti.
- Risultato atteso: gli update pipeline parziali devono aggiornare solo i campi presenti e preservare i blocchi/testi gia' persistiti quando l'update non li rimanda.
- Causa probabile: `sync_assistant_pipeline_state` sostituiva l'intero `MainChatStoreMessageSnapshot` con `pipeline_message`, preservando solo il primary text quando lo snapshot in ingresso era vuoto.
- Scope consentito:
  - `Native/RustCore/src/main_chat/store/messages/assistant.rs`
  - `Native/RustCore/src/main_chat/store/tests/messages.rs`
- Non-scope:
  - view SwiftUI della timeline
  - `ToolTraceStore`
  - protocollo bridge Swift/Rust
- Moduli confinanti da verificare:
  - store reducers main chat
  - normalizzazione blocchi primary/reasoning
  - commit persistito dei pipeline events
- Test da aggiungere o aggiornare:
  - regression test per partial snapshot che preserva primary text, reasoning, command blocks e subagent cards
- Strategia di fix minimo:
  - fare merge dei `blocks` esistenti con quelli incoming
  - preservare `reasoning_text` e `subagent_cards` quando lo snapshot pipeline non li include
  - mantenere la normalizzazione gia' esistente di primary/reasoning
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml sync_assistant_pipeline_state_preserves_existing_timeline_context_when_incoming_snapshot_is_partial -- --nocapture`
  - `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::store::tests::messages -- --nocapture`
- Commit previsto: `fix(main-chat): preserve timeline state across partial pipeline snapshots`
