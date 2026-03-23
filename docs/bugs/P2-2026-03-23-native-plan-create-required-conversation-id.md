# P2 - Il backend Rust nativo dei plan tools falliva senza conversation_id al bootstrap

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: i plan tools sul server MCP Rust nativo non riallineati al vecchio wrapper Swift richiedevano `conversation_id` anche nei casi in cui il contesto poteva essere derivato o creato in modo sicuro; il primo sintomo visibile era `coderide_plan_create` in errore.
- Sintomo:
  - il trace mostrava `todo_write` completato
  - `plan_create` falliva con `Error: 'conversationId' is required`
  - il plan panel restava rosso/non aggiornato nel flusso iniziale
- Impatto: impediva l'avvio della pianificazione nativa nel path MCP Rust, con alto rischio di far fallire subito anche mutazioni successive come `plan_step_upsert`, `plan_step_batch_update`, `plan_step_dependency_set` e `plan_set_walkthrough` quando `conversation_id` non veniva passato esplicitamente.
- Gravita': P2
- Steps to reproduce:
  1. Avviare una sessione nuova senza snapshot plan esistenti.
  2. Emettere `coderide_todo_write`.
  3. Emettere `coderide_plan_create` con `goal` e `steps`, ma senza `conversation_id`.
  4. Osservare il fallimento del tool.
- Risultato attuale: [plan_state.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/plan_state.rs) richiedeva sempre `conversation_id` per quasi tutte le mutazioni piano nel core Rust condiviso.
- Risultato atteso: `coderide_plan_create` e le mutazioni piano affini devono:
  - usare l'id esplicito se fornito
  - riusare l'unico contesto plan esistente se non ambiguo
  - creare un nuovo `conversation_id` valido se non esiste ancora alcun piano
- Causa probabile: parita' incompleta tra wrapper Swift dei plan tools e implementazione nativa Rust del core piano condiviso.
- Scope consentito:
  - `Native/RustCore/src/plan_state.rs`
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
  - unit test Rust su `plan_state`
  - smoke test MCP Rust per `coderide_plan_create` senza `conversation_id`
- Strategia di fix minimo:
  - introdurre nel core Rust condiviso la stessa risoluzione di `conversation_id` del wrapper Swift per le mutazioni piano: esplicito, unico snapshot esistente, oppure nuovo UUID valido se il documento e' vuoto.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml plan_state -- --nocapture` -> OK
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml plan_create_without_conversation_id_bootstraps_new_plan_context -- --exact` -> bloccato da errore di sintassi preesistente in `Native/CoderideMCPServerRust/src/debug_tools.rs`
- Commit previsto:
  - `fix(plan): bootstrap rust plan conversation id`
