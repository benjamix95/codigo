# 2026-03-23 - Native Rust plan_create bootstrap

## Modifiche
- corretto `coderide_plan_create` nel server MCP Rust nativo per non richiedere piu' sempre `conversation_id` al primo bootstrap.
- aggiunto fallback coerente con il wrapper Swift:
  - usa `conversation_id` esplicito se presente
  - riusa l'unico contesto plan esistente se non ambiguo
  - genera un nuovo id valido se non esiste ancora alcuno snapshot
- aggiunta regression test `plan_create_without_conversation_id_bootstraps_new_plan_context`.

## Verifica
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_create_without_conversation_id_bootstraps_new_plan_context -- --exact`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_tools_and_ide_acks_work -- --exact`
