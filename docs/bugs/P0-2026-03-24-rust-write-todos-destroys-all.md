# P0 — write_todos con singolo title distrugge tutti i todo esistenti

## Bug Fix Record
- Categoria: A - Critico
- Bug: `write_todos` in `shared_state.rs` quando riceve un singolo `title` (senza `todos_value` come array JSON) chiama `write_json_array(vec![item])`, sovrascrivendo l'intero file todo con un solo elemento.
- Sintomo: Aggiungere un todo singolo via il parametro `title` cancella tutti i todo precedenti.
- Impatto: Perdita dati completa della lista todo. L'utente perde tutto il tracking del lavoro.
- Gravità: P0
- Steps to reproduce:
  1. Avere 10 todo esistenti nel file todo.
  2. Chiamare il tool `coderide_todo` con `title: "nuovo task"` (senza `todos` array).
  3. Verificare che il file todo contiene solo 1 elemento: "nuovo task".
- Risultato attuale: `write_json_array(vec![item])` sostituisce l'intero contenuto con un array di 1 elemento.
- Risultato atteso: Il nuovo todo deve essere **aggiunto** alla lista esistente, non sostituirla.
- Causa probabile: Il branch di codice per singolo title non legge prima la lista esistente per fare append.
- Scope consentito: `Native/CoderideMCPServerRust/src/shared_state.rs` — funzione `write_todos`, linee 88-104.
- Non-scope: UI todo, persistence store, MCPSharedState Swift.
- Moduli confinanti da verificare: `read_todos` (per verificare il formato atteso), tool `coderide_todo` (per verificare i parametri passati).
- Test da aggiungere o aggiornare:
  - Test: write 3 todo, poi write 1 singolo title → file contiene 4 todo.
  - Test: write singolo title su file vuoto → file contiene 1 todo.
  - Test: write array JSON completo → sovrascrittura corretta (comportamento voluto).
- Strategia di fix minimo: Nel branch singolo-title, leggere prima la lista esistente con `read_todos()`, appendere il nuovo item, poi scrivere l'array completo.
- Verifica post-fix:
  1. Unit test append singolo title su lista esistente.
  2. `cargo test` sull'intero crate.
  3. Smoke test manuale: aggiungere todo singoli senza perdere quelli esistenti.
- Commit previsto: `fix(mcp-rust): append single todo instead of overwriting entire list`
