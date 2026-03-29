# P1 - `todo_write` batch riusa il `taskId` come ID di tutti i todo

## Bug Fix Record
- Categoria: B - Importante
- Bug: il bridge raw `todo_write` usava `payload.taskId` come fallback ID anche quando un singolo evento conteneva piu' todo in `todos_json`.
- Sintomo: in un batch senza `id` item-level, i todo successivi sovrascrivono il precedente invece di creare righe distinte.
- Impatto: perdita o corruzione dello stato runtime/canonical; avanzamento errato della coda e mismatch tra UI e store.
- Gravita': P1
- Steps to reproduce:
  1. Avvia una pipeline con runtime TODO attivo.
  2. Invia un raw event `todo_write` con `todos_json` contenente almeno due item senza `id`.
  3. Usa un `taskId` parsabile come UUID.
- Risultato attuale: tutti gli item del batch condividono lo stesso fallback ID e finiscono sulla stessa riga.
- Risultato atteso: ogni item del batch deve avere identita' autonoma, oppure nessun fallback condiviso.
- Causa probabile: `resolvedRawTodoID(...)` ritornava sempre `UUID(uuidString: payload.taskId)` quando `parsedTodo.id` mancava, senza distinguere evento singolo da batch.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+TodoRawEventSupport.swift`
  - regression test pipeline TODO batch
- Non-scope:
  - refactor del normalizer
  - policy di refresh UI chat
- Moduli confinanti da verificare:
  - `TodoStore.upsertFromAgent`
  - `TodoStore.upsertCanonicalOnlyFromAgent`
  - `EventNormalizer.normalizeTodoWrite`
- Test da aggiungere o aggiornare:
  - regression test per `todo_write` batch con `todos_json` e `taskId` UUID-like
- Strategia di fix minimo:
  - consentire il fallback `taskId -> UUID` solo per eventi con un singolo todo;
  - nei batch senza `id` lasciare `nil`, delegando allo store la generazione di ID per-item.
- Verifica post-fix:
  - test dedicato `PipelineIntegrationTodoBatchTests`
- Commit previsto:
  - `fix(todo): avoid shared fallback ids in todo_write batches`
