# P2 - Il backend Rust nativo di plan_create falliva senza conversation_id

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: `coderide_plan_create` sul server MCP Rust nativo richiedeva sempre `conversation_id`, causando il fallimento del primo bootstrap plan in chat anche quando la todo iniziale era corretta.
- Sintomo:
  - il trace mostrava `todo_write` completato
  - `plan_create` falliva con `Error: 'conversationId' is required`
  - il plan panel restava rosso/non aggiornato nel flusso iniziale
- Impatto: impediva l'avvio della pianificazione nativa nel path MCP Rust, con UX incoerente rispetto al wrapper Swift e rispetto alle policy della chat.
- Gravita': P2
- Steps to reproduce:
  1. Avviare una sessione nuova senza snapshot plan esistenti.
  2. Emettere `coderide_todo_write`.
  3. Emettere `coderide_plan_create` con `goal` e `steps`, ma senza `conversation_id`.
  4. Osservare il fallimento del tool.
- Risultato attuale: `Native/CoderideMCPServerRust/src/plan_state.rs` usava `required_conversation_id(arguments)?` in `create_snapshot`.
- Risultato atteso: `coderide_plan_create` deve:
  - usare l'id esplicito se fornito
  - riusare l'unico contesto plan esistente se non ambiguo
  - creare un nuovo `conversation_id` valido se non esiste ancora alcun piano
- Causa probabile: parita' incompleta tra wrapper Swift dei plan tools e implementazione nativa Rust del server MCP.
- Scope consentito:
  - `Native/CoderideMCPServerRust/src/plan_state.rs`
  - `Native/CoderideMCPServerRust/tests/server_smoke.rs`
- Non-scope:
  - flow UI del plan panel
  - store Swift del plan board
  - policy todo-first
- Moduli confinanti da verificare:
  - `coderide_plan_read`
  - `coderide_plan_step_upsert`
  - bootstrap del primo snapshot plan
- Test da aggiungere o aggiornare:
  - smoke test MCP Rust per `coderide_plan_create` senza `conversation_id`
- Strategia di fix minimo:
  - introdurre fallback locale in `create_snapshot` per risolvere o generare un `conversation_id` valido quando manca.
- Verifica post-fix:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_create_without_conversation_id_bootstraps_new_plan_context -- --exact`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_tools_and_ide_acks_work -- --exact`
- Commit previsto:
  - `fix(plan): bootstrap conversation id in native rust mcp server`
