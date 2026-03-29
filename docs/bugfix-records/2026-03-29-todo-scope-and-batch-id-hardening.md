# Bug Fix Record — 2026-03-29 — TODO batch ID e scope canonical

- **Categoria:** B — Importante
- **Bug:** il bridge pipeline TODO aveva due punti fragili: collisione ID nei batch `todo_write` senza `id` espliciti e fallback dei canonical legacy visibile in conversazioni scoped non correlate.
- **Sintomo:** un batch `todos_json` poteva lasciare una sola riga aggiornata invece di piu' todo distinti; inoltre un nuovo thread plan poteva vedere step legacy non suoi.
- **Impatto:** corruzione dello stato TODO, auto-avanzamento incoerente e contaminazione cross-conversation nella board plan.
- **Gravita':** P1
- **Steps to reproduce:**
  1. Invia un raw `todo_write` con `todos_json` contenente piu' item senza `id` e `taskId` UUID-like.
  2. Interroga i todo runtime dopo il processing del batch.
  3. In un altro scenario, salva un canonical legacy unscoped, poi un canonical scoped su una chat diversa, quindi chiedi `canonicalTodos(for:)` per una terza chat vuota.
- **Risultato attuale:** il batch puo' riusare lo stesso fallback ID per tutti gli item; lo scope canonical puo' fare fallback legacy anche quando esistono gia' canonical scoped altrove.
- **Risultato atteso:** ogni item del batch deve mantenere identita' autonoma; i canonical legacy devono comparire solo nei veri flussi legacy senza scope.
- **Causa probabile:** fallback `payload.taskId -> UUID` applicato indiscriminatamente nei batch e fallback legacy sempre attivo in `canonicalTodos(for:)`.
- **Scope consentito:** `PipelineIntegrationService+TodoRawEventSupport.swift`, `TodoStore+Queries.swift`, nuovi regression test dedicati e documentazione del fix.
- **Non-scope:** ottimizzazioni performance della chat, refactor del normalizer, patch Rust TODO adapter.
- **Moduli confinanti da verificare:** `TodoStore+PlanExecutionProgression.swift`, `TodoStore+RuntimeExecutionProgression.swift`, `EventNormalizerTodoTests`.
- **Test da aggiungere o aggiornare:** regression test batch raw TODO e regression test scope canonical legacy.
- **Strategia di fix minimo:** consentire il fallback `taskId` solo per eventi singoli; limitare il fallback legacy dei canonical ai soli store senza alcun canonical scoped.
- **Verifica post-fix:** test mirati `PipelineIntegrationTodoBatchTests`, `TodoStoreCanonicalScopeTests` e controllo sul normalizer TODO gia' presente.
- **Commit previsto:** `fix(todo): harden batch ids and canonical scope fallback`
