# 2026-03-23 — Main chat timeline partial snapshot preservation

## Modifiche
- corretto `sync_assistant_pipeline_state` per evitare che uno snapshot pipeline parziale sovrascriva il contenuto storico gia' persistito del messaggio assistant
- aggiunto merge dei `blocks` esistenti con quelli incoming, mantenendo replacement per id/kind e preservando i blocchi non presenti nello snapshot parziale
- preservati `reasoning_text` e `subagent_cards` quando l'update pipeline non li rimanda
- mantenuta la normalizzazione dei blocchi `primaryText` e `reasoning` dopo il merge

## Test
- `cargo test --manifest-path Native/RustCore/Cargo.toml sync_assistant_pipeline_state_preserves_existing_visible_text_when_incoming_is_empty -- --nocapture`
- `cargo test --manifest-path Native/RustCore/Cargo.toml sync_assistant_pipeline_state_preserves_existing_timeline_context_when_incoming_snapshot_is_partial -- --nocapture`
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::store::tests::messages -- --nocapture`

## Note
- `cargo fmt --manifest-path Native/RustCore/Cargo.toml` non e' eseguibile in questo ambiente perche' il componente `rustfmt` non e' installato sulla toolchain corrente.
