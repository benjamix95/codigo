# P1 - Fallback canonical legacy visibile in conversazioni scoped non correlate

## Bug Fix Record
- Categoria: B - Importante
- Bug: `canonicalTodos(for:)` tornava i canonical legacy unscoped anche per nuove conversazioni scoped che non avevano ancora un piano proprio.
- Sintomo: aprendo un thread plan nuovo o una chat con `planConversationId` diverso, potevano comparire step legacy di un altro contesto.
- Impatto: contaminazione cross-conversation, plan board sporca, resume e auto-advance basati su todo non appartenenti al thread attivo.
- Gravita': P1
- Steps to reproduce:
  1. Persisti almeno un canonical legacy con `planConversationId == nil`.
  2. Persisti almeno un altro canonical scoped su una conversazione differente.
  3. Richiama `canonicalTodos(for:)` per una terza conversazione scoped ancora vuota.
- Risultato attuale: il metodo restituisce i canonical legacy unscoped.
- Risultato atteso: il fallback legacy deve valere solo quando non esistono canonical scoped da nessuna parte, cioe' nel caso di migrazione legacy reale.
- Causa probabile: `canonicalTodos(for:)` faceva fallback silenzioso a `planConversationId == nil` ogni volta che lo scope richiesto era vuoto.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Queries.swift`
  - regression test dedicato `TodoStore`
- Non-scope:
  - runtime todos
  - patch Rust store adapter
- Moduli confinanti da verificare:
  - `TodoStore+PlanExecutionProgression.swift`
  - `TodoStore+RuntimeExecutionProgression.swift`
  - sincronizzazione `chatStore.syncPlanStepsFromCanonicalTodos`
- Test da aggiungere o aggiornare:
  - regression test che impedisca bleed cross-conversation
  - test che preservi il fallback legacy puro in assenza di canonical scoped
- Strategia di fix minimo:
  - restituire il fallback legacy solo se la collezione canonical non contiene nessun `planConversationId` valorizzato.
- Verifica post-fix:
  - test dedicato `TodoStoreCanonicalScopeTests`
- Commit previsto:
  - `fix(todo): scope canonical legacy fallback to true legacy flows`
