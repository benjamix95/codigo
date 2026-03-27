# Plan Panel / Todo Bottlenecks Remediation — 2026-03-27

## Bug Fix Record
- Categoria: A/B
- Bug: il sottosistema `Plan/Panel/PlanFlow/Chat/Todo` aveva piu' choke point combinati: query todo ridondanti, persistenza troppo frequente, sync multipli store-to-store e invalidazioni chat troppo aggressive.
- Sintomo:
  1. jank e lavoro inutile durante `todo_write` e aggiornamenti plan
  2. costo crescente con il numero di todo/thread
  3. persistenze ripetute nello stesso evento runtime
  4. churn UI non necessario su `todo_read`
- Impatto:
  - peggioramento della reattivita' del Plan Panel e della chat
  - spreco di CPU/main thread su percorsi molto caldi
  - maggiore rischio di regressioni quando plan/todo si aggiornano ad alta frequenza
- Gravita': alta
- Steps to reproduce:
  1. attivare una sessione con molti `todo_write` o con `plan_step_batch_update`
  2. osservare che la chat e i panel aggiornano piu' volte lo stesso stato
  3. verificare che un singolo evento possa innescare piu' salvataggi e piu' sync del board
- Risultato attuale:
  - snapshot todo e policy chat ricostruiti in modo piu' compatto
  - persistenza dei todo batchata nei path runtime caldi
  - sync canonical todo -> plan board coalesciato nei path bulk
  - `todo_read` non invalida piu' la timeline chat
- Risultato atteso:
  - un solo commit di persistenza per batch logico
  - policy chat O(n) invece di ricalcoli interni ripetuti
  - meno lavoro UI per eventi solo diagnostici/metadato
- Causa probabile:
  - la logica era corretta funzionalmente ma ogni layer ricalcolava e persisteva per conto proprio
  - mancava batching nei path `todo_write` / `plan_create` / pipeline raw
  - la policy chat riusava un helper nato per correttezza, non per hot path
- Scope consentito:
  - `TodoStore`
  - policy chat dei todo
  - handlers chat/pipeline per eventi todo/plan
  - plan panel lightweight policy
  - test di regressione
- Non-scope:
  - redesign completo del multi-turn `PlanFlow`
  - refactor architetturale totale del bridge Rust
  - rework del rendering markdown del panel
- Moduli confinanti da verificare:
  - `TodoStoreTests`
  - `TodoChatDisplayPolicyTests`
  - `PipelineIntegrationServiceTests`
  - `ChatTodoVisibilityTests`
- Test da aggiungere o aggiornare:
  - batching del `TodoStore`
  - coerenza policy snapshot vs policy legacy
  - invalidazione chat su `todo_read`
- Strategia di fix minimo:
  1. introdurre snapshot/caching condiviso per la policy chat dei todo
  2. introdurre `performBatchUpdates` nel `TodoStore`
  3. usare batching nei path runtime piu' caldi
  4. eliminare un prepare ridondante nel passaggio phase2 -> phase3 del plan flow
  5. evitare state write inutile nella cache auth del Plan Panel
- Verifica post-fix:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/TodoStorePersistenceTests -only-testing:SoloCodeAppTests/TodoChatDisplayPolicyTests -only-testing:SoloCodeAppTests/TodoStoreMutationBatchingTests -only-testing:SoloCodeAppTests/TodoChatDisplayScopeSnapshotTests -only-testing:SoloCodeAppTests/ChatTimelineInvalidationPolicyTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
- Commit previsto:
  - fix(plan): batch todo mutations and reduce chat invalidations

## Fix applicati

### P1 — Query todo della chat ottimizzate
- introdotto `TodoChatDisplayScopeSnapshot` come snapshot condiviso per la policy chat.
- eliminato il ricalcolo `visibleTodos.filter { ... }` dentro la policy per ogni item.

### P1 — Persistenza todo batchata
- introdotto `TodoStore.performBatchUpdates`.
- i path caldi (`handleTodoWriteEvent`, raw pipeline todo, bulk sync plan) ora fanno un solo flush persistente per batch logico.

### P1 — Sync bulk plan/todo coalesciato
- `plan_create` e `plan_step_batch_update` raccolgono gli scope da sincronizzare e aggiornano il board una sola volta per conversazione.

### P1 — Invalidazione chat ridotta
- `todo_read` non incrementa piu' `streamContentVersion`.
- resta invariata l'invalidazione per `todo_write`, che e' l'evento che muove davvero la card live.

### P2 — Micro-churn rimosso nel Plan Flow / Plan Panel
- rimosso un `plan_prepare_phase3_generation_prompt` ridondante nel passaggio phase2 -> phase3.
- `refreshProviderAuthCache()` non scrive piu' stato quando la cache non cambia davvero.
