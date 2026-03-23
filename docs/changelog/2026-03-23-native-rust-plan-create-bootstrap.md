# 2026-03-23 - Native Rust plan bootstrap conversation id

## Modifiche
- corretto il core Rust condiviso dei plan tools per non richiedere piu' sempre `conversation_id` al primo bootstrap del piano.
- allineata la risoluzione del contesto piano alle regole gia' usate dal wrapper Swift per `plan_create`, `plan_step_update`, `plan_step_upsert`, `plan_step_batch_update`, `plan_step_reorder`, `plan_step_dependency_set` e `plan_set_walkthrough`.
- aggiunto fallback coerente con il wrapper Swift:
  - usa `conversation_id` esplicito se presente
  - riusa l'unico contesto plan esistente se non ambiguo
  - genera un nuovo id valido se non esiste ancora alcuno snapshot
- aggiunti regression test Rust per bootstrap senza `conversation_id`, riuso del contesto unico e fallimento corretto su ambiguita'.

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml plan_state -- --nocapture`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_create_without_conversation_id_bootstraps_new_plan_context -- --exact` non eseguibile fino a correzione del file [`debug_tools.rs`](/Users/benjaminstoica/SoloCode/Native/CoderideMCPServerRust/src/debug_tools.rs), che oggi fallisce in compilazione per parentesi sbilanciate fuori scope da questo fix
