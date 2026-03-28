# P1 - Il runtime plan poteva usare una conversazione stale quando la request indicava un'altra conversation

## Bug Fix Record
- Priorità: P1
- Categoria: B - Importante ma non bloccante
- Bug: `apply_plan_runtime_action` lasciava invariata `selected_conversation_id` quando esisteva gia' una selezione non vuota, anche se la request `apply_plan_runtime_action` arrivava con una `conversation_id` diversa e senza `runtime_snapshot`.
- Sintomo:
  - una request plan poteva agganciarsi alla conversazione precedentemente selezionata
  - il seed dello `MainChatRuntimeSnapshot` poteva nascere con `conversation_id` errata
  - il plan panel mostrava stato coerente con la request corrente solo in parte, ma il routing runtime restava sulla conversazione vecchia
- Impatto: rischio di applicare una intenzione plan al thread sbagliato in scenari multi-conversation o dopo riuso di stato UI.
- Gravita': alta
- Steps to reproduce:
  1. Portare `selected_conversation_id` su `conv-A`.
  2. Azzerare `runtime_snapshot`.
  3. Inviare `apply_plan_runtime_action` con `conversation_id = conv-B`.
  4. Osservare che il runtime seed poteva restare agganciato a `conv-A`.
- Risultato attuale: la request esplicita non prevaleva sulla selezione stale se questa non era vuota.
- Risultato atteso: in assenza di `runtime_snapshot`, la `conversation_id` della request deve diventare la sorgente di verita' per il runtime seed del plan.
- Causa probabile: il sync iniziale in `apply_plan_runtime_action` aggiornava `selected_conversation_id` solo nel caso di valore vuoto o whitespace.
- Scope consentito:
  - `Native/RustCore/src/main_chat/plan_ui_flow.rs`
  - `Native/RustCore/src/main_chat/ui_tests.rs`
  - documentazione bug/changelog
- Non-scope:
  - logging NDJSON
  - refactor del projection layer UI
  - cambiamenti al reducer store chat
- Moduli confinanti da verificare:
  - seed di `runtime_snapshot_for_plan_action`
  - projection UI del plan panel
  - errore `missing_conversation_for_plan`
- Test da aggiungere o aggiornare:
  - regressione Rust: la request `conversation_id` deve sovrascrivere una selezione stale quando manca `runtime_snapshot`
  - conferma del path gia' esistente che richiede `conversation_id` se lo snapshot manca del tutto
- Strategia di fix minimo:
  - far prevalere `request.conversation_id` quando non esiste `runtime_snapshot`
  - mantenere il comportamento precedente quando il runtime snapshot esiste gia'
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml ui_intent_plan_phase0_ -- --nocapture`
- Commit previsto: `fix(plan): prefer request conversation when seeding runtime`
