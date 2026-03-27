# Analisi Colli di Bottiglia — Plan, Panel, PlanFlow, Chat e Todo

**Data**: 2026-03-27
**Scope**: attivazione del Plan dalla chat, rendering del Plan Panel, `PlanFlow`, todo del Plan e todo della chat
**Tipo**: analisi read-only, nessuna modifica runtime applicata

---

## Executive summary

L’area più costosa non è un singolo metodo, ma la combinazione di:

1. **PlanFlow seriale a più round LLM**
2. **Invalidazione aggressiva della timeline chat su ogni evento plan/todo**
3. **`TodoStore` con query e persistenza full-scan/full-write quasi a ogni mutazione**
4. **Sincronizzazioni duplicate tra `TodoStore`, `ChatStore` e panel**

Il risultato probabile è:

- latenza elevata quando la chat entra in plan mode
- jank UI durante streaming / update plan step / update todo
- costo che cresce male con numero di thread, numero di todo e frequenza eventi

---

## BOTTLENECK-PP-01 — Attivazione del Plan troppo seriale e con round-trip duplicati

**Priorità**: P1
**Area**: chat -> plan activation -> plan generation
**File**:
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase0.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase1.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase2.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift`

**Sintomo**
- L’attivazione del Plan dalla chat passa fino a 4 stream sequenziali: screening, analisi, domande, generazione.
- In fase 3 ci sono fino a 2 retry di repair, quindi il costo può salire a 5-6 round-trip LLM prima di avere un piano pronto.

**Evidenza**
- Phase 0 screening: `runStream` + `planRuntimeAction("plan_apply_screening_result")` in [ChatPanelView+PartM_MultiTurnPlanFlowPhase0.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase0.swift#L20)
- Phase 1 analysis: altro `runStream` + `planRuntimeAction("plan_apply_analysis_result")` in [ChatPanelView+PartM_MultiTurnPlanFlowPhase1.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase1.swift#L18)
- Phase 2 clarification: altro `runStream` + `planRuntimeAction("plan_apply_question_result")` in [ChatPanelView+PartM_MultiTurnPlanFlowPhase2.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_MultiTurnPlanFlowPhase2.swift#L18)
- Phase 3 generation: altro `runStream` + possibili retry in loop `while ... repairAttempt < maxRepairAttempts` in [ChatPanelView+PartM_Phase3.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift#L16) e [ChatPanelView+PartM_Phase3.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartM_Phase3.swift#L146)

**Perché è un collo di bottiglia**
- Ogni fase aspetta la precedente.
- Ogni fase rientra sul `MainActor` per stato/chat/runtime snapshot.
- Il piano viene “parseato/applicato” più volte nello stesso percorso solo per capire se proseguire.

**Impatto**
- Tempo percepito molto alto quando l’utente attiva il plan dalla chat.
- Alta sensibilità a provider lenti o stream verbose.
- UX peggiora soprattutto nei casi che richiedono chiarimenti o repair.

**Direzione fix**
- Unificare screening + analysis in una singola fase quando possibile.
- Eseguire la validazione del formato plan in-stream invece di un repair stream separato.
- Ridurre le transizioni `runStream -> trim -> MainActor -> planRuntimeAction` a un solo commit per fase terminale.

---

## BOTTLENECK-PP-02 — Eventi plan/todo invalidano tutta la timeline chat troppo spesso

**Priorità**: P1
**Area**: live chat rendering durante plan/todo
**File**:
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift`

**Sintomo**
- Eventi come `todo_write`, `todo_read`, `plan_step_upsert`, `plan_request_user_input` incrementano sempre `streamContentVersion`.
- Ogni incremento scatena `refreshMessagesSnapshot()` sull’area messaggi.

**Evidenza**
- Invalidazione globale per quasi tutti gli eventi plan/todo in [ChatPanelSupport+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift#L217)
- Ogni handler plan incrementa `streamContentVersion` in [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L69), [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L90), [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L122), [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L229)
- `todo_write` e perfino `todo_read` fanno lo stesso in [ChatPanelView+PartF_TodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift#L117)
- `streamContentVersion` richiama subito `refreshMessagesSnapshot()` in [ChatPanelView+PartC_MessageAreaRefreshModifiers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift#L13)
- `refreshMessagesSnapshot()` rilegge conversazione, loading, trace, live activity e fa correzioni/safety net extra in [ChatPanelView+PartC_MessageSnapshotRefresh.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift#L9)

**Perché è un collo di bottiglia**
- La timeline chat viene trattata come se ogni mutazione plan/todo fosse equivalente a un delta testo.
- `todo_read` è quasi sempre un evento di metadato, ma fa lo stesso lavoro di una mutazione visiva reale.
- Il refresh non è cheap: ricontrolla stato chat, store, trace e live activity.

**Impatto**
- Re-render e scroll sync inutili.
- Maggior rischio di lag/stutter mentre il plan è attivo.
- Aumento del lavoro sul main thread proprio durante lo streaming.

**Direzione fix**
- Separare invalidazioni `chat text`, `task activity`, `todo cards`, `plan panel`.
- Non far salire `streamContentVersion` per `todo_read`.
- Usare tick distinti per plan/todo panel invece della stessa leva della timeline messaggi.

---

## BOTTLENECK-PP-03 — `TodoStore.displayTodosForChat` scala male e diventa O(n^2)

**Priorità**: P1
**Area**: todo della chat, todo del plan, sidebar thread list
**File**:
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Queries.swift`
- `App/SoloCodeApp/Sources/Tasking/Policy/TodoChatDisplayPolicy.swift`
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadRenderState.swift`
- `App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel+Standard.swift`

**Sintomo**
- Per ogni chat si filtra `visible`.
- Per ogni item filtrato, la policy ricrea `scoped = visibleTodos.filter { ... }`.
- La sidebar ripete la stessa operazione per ogni conversazione.

**Evidenza**
- `displayTodosForChat(for:)` costruisce `planScopeIds` e poi fa `visible.filter { TodoChatDisplayPolicy.itemAppearsInChat(...) }` in [TodoStore+Queries.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Queries.swift#L71)
- Dentro `itemAppearsInChat`, per ogni item viene rifatto `visibleTodos.filter { $0.planConversationId == conversationId }` in [TodoChatDisplayPolicy.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Policy/TodoChatDisplayPolicy.swift#L19)
- La sidebar richiama `displayTodosForChat` per ogni thread in [SidebarThreadRenderState.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadRenderState.swift#L88)
- Anche `TaskActivityPanel` richiama `displayTodosForChat` durante il rendering live in [TaskActivityPanel+Standard.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Views/TaskStatus/TaskActivityPanel+Standard.swift#L5)

**Perché è un collo di bottiglia**
- Complessità effettiva vicina a O(n^2) per snapshot di una singola conversazione.
- Con più thread aperti, la sidebar moltiplica il costo per il numero conversazioni.
- La cache aiuta solo dopo il primo calcolo, ma viene invalidata da qualsiasi `didSet` di `todos`.

**Impatto**
- CPU inutile quando arrivano molti todo update.
- Sidebar e pannelli diventano progressivamente più costosi con l’aumentare dei thread.

**Direzione fix**
- Precomputare uno snapshot indicizzato per `conversationId`.
- Passare a `TodoChatDisplayPolicy` il booleano `hasScopedForConversation` già calcolato.
- Mantenere cache per conversation + revision invece di invalidare tutto su ogni singola mutazione.

---

## BOTTLENECK-PP-04 — `TodoStore` persiste e risincronizza tutto quasi a ogni singolo update

**Priorità**: P1
**Area**: todo del plan e todo della chat
**File**:
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Mutations.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`

**Sintomo**
- Quasi ogni branch di upsert chiama `saveTodos()`.
- `saveTodos()` serializza tutti i todo visibili e pianifica sync verso shared state.
- Un singolo `todo_write` può causare: upsert, follow-up auto-generated, advance next runtime todo, sync plan steps.

**Evidenza**
- `upsertFromAgent` chiama `saveTodos()` in più rami in [TodoStore+Mutations.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Mutations.swift#L29)
- `upsertCanonicalOnlyFromAgent` fa lo stesso in [TodoStore+Mutations.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Mutations.swift#L131)
- `saveTodos()` serializza tutto `visibleTodos`, scrive su `UserDefaults` e poi `MCPSharedState.writeTodos(items)` in [TodoStore+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift#L71) e [TodoStore+Persistence.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+Persistence.swift#L132)
- `handleTodoWriteEvent` può aggiungere follow-up e auto-advance nello stesso evento in [ChatPanelView+PartF_TodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift#L70)
- Il path pipeline raw fa upsert/advance/sync analoghi in [PipelineIntegrationService+EventSupport.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift#L143)

**Perché è un collo di bottiglia**
- La granularità di persistenza è troppo fine.
- Lo store fa full-write anche per micro-update di stato.
- Le mutazioni vengono duplicate in due ingressi diversi: raw pipeline e raw chat trace.

**Impatto**
- Più I/O del necessario.
- Più invalidazioni SwiftUI del necessario.
- Più probabilità di burst quando il modello emette molti `todo_write`.

**Direzione fix**
- Introdurre transazioni/batch mutate-then-save.
- Debounce locale del persistence layer, non solo shared-state sync.
- Separare `dirty runtime todos` e `dirty canonical todos` con flush aggregato.

---

## BOTTLENECK-PP-05 — Sincronizzazione `TodoStore` <-> `ChatStore` duplicata e ripetitiva

**Priorità**: P2
**Area**: plan steps, canonical todos, board sync
**File**:
- `App/SoloCodeApp/Sources/Services/ChatStore/Plans/ChatStorePlans.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+DisplayFlags.swift`

**Sintomo**
- Dopo molti update todo/plan viene ricalcolato `canonicalTodos(for:)` e poi riscritto `PlanBoard`.
- Lo stesso sync parte da più punti del sistema.

**Evidenza**
- `syncPlanStepsFromCanonicalTodos` rifiltra, riordina e persiste la board in [ChatStorePlans.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Plans/ChatStorePlans.swift#L165)
- Il raw pipeline richiama `canonicalTodos(for:)` e `syncPlanStepsFromCanonicalTodos` in [PipelineIntegrationService+EventSupport.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift#L187)
- Il path chat trace fa la stessa cosa in [ChatPanelView+PartF_TodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift#L63)
- Esiste anche sync bidirezionale su callback `onCanonicalTodoStatusChange` in [ChatPanelView+DisplayFlags.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatInteraction/ChatBindings/ChatPanelView+DisplayFlags.swift#L4)

**Perché è un collo di bottiglia**
- Più ingressi fanno lo stesso lavoro di mapping e persistenza.
- Non c’è una singola ownership del passaggio “canonical todo -> plan board”.
- Ogni update done/in_progress può innescare più sync a cascata.

**Impatto**
- Scritture ridondanti.
- Stato più difficile da ragionare e da profilare.
- Rischio di regressioni/rimbalzi quando si tocca un solo pezzo del flow.

**Direzione fix**
- Centralizzare il bridge `canonical todo -> plan board` in un solo reducer/service.
- Evitare sync immediato su ogni step se cambia solo un `status`.
- Usare diff incrementale sul board invece di rebuild/merge completo.

---

## BOTTLENECK-PP-06 — `PlanPanelView` fa lavoro costoso nel body durante streaming

**Priorità**: P2
**Area**: Plan Panel rendering
**File**:
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift`
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Layout.swift`

**Sintomo**
- Il panel osserva tre store (`todoStore`, `chatStore`, `taskActivityStore`) e nel `body` ricompone snapshot, activity, parser e mermaid.
- Inoltre ricalcola spesso la cache auth provider su notifiche generiche del registry.

**Evidenza**
- Il panel dipende direttamente da più store osservabili in [PlanPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift#L8)
- `planTraceActivities` ricava e rifiltra attività ogni body pass in [PlanPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift#L71)
- `resolveSnapshot()` dipende da `displayPlanContent`, hash del contenuto e todo fingerprint in [PlanPanelView+Content.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift#L65)
- `makeRenderSnapshot()` riparsa body e mermaid dal testo corrente in [PlanPanelView+Content.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Content.swift#L80)
- `refreshProviderAuthCache()` riesegue `isAuthenticated()` per tutti i provider consentiti in [PlanPanelView+Layout.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView+Layout.swift#L188)
- Questo refresh parte su `providerRegistry.objectWillChange` in [PlanPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift#L195)

**Perché è un collo di bottiglia**
- Durante streaming plan, il panel ricalcola contenuto proprio mentre la chat invalida lo stato.
- Parsing markdown/mermaid nel body è costoso quando il testo cresce.
- La cache snapshot evita solo parte del lavoro, ma la chiave stessa dipende da contenuto e todo fingerprint.

**Impatto**
- Plan Panel pesante da aprire e aggiornare.
- Main thread più carico nelle fasi `analyzing/questioning/generating`.

**Direzione fix**
- Spostare parsing markdown/mermaid fuori dal body con precompute incrementale.
- Limitare `providerAuthCache` a cambi provider reali, non a ogni `objectWillChange`.
- Separare sotto-view per `trace`, `history`, `content`, `todos` con input già derivati.

---

## Riepilogo Priorità

| Priorità | ID | Area | Impatto principale |
|----------|----|------|--------------------|
| P1 | BOTTLENECK-PP-01 | PlanFlow activation | Latenza end-to-end alta |
| P1 | BOTTLENECK-PP-02 | Chat invalidation | Re-render e refresh inutili |
| P1 | BOTTLENECK-PP-03 | Todo query model | Complessità O(n^2) |
| P1 | BOTTLENECK-PP-04 | Todo persistence | Full-write troppo frequenti |
| P2 | BOTTLENECK-PP-05 | Store sync duplication | Rimbalzi tra store |
| P2 | BOTTLENECK-PP-06 | Plan Panel rendering | Costo UI durante streaming |

---

## Ordine di intervento suggerito

1. Ridurre le invalidazioni chat (`BOTTLENECK-PP-02`)
2. Batchare query/persistenza todo (`BOTTLENECK-PP-03`, `BOTTLENECK-PP-04`)
3. Centralizzare sync canonical todo -> plan board (`BOTTLENECK-PP-05`)
4. Solo dopo: comprimere il multi-turn plan flow (`BOTTLENECK-PP-01`)
5. Infine alleggerire il rendering del panel (`BOTTLENECK-PP-06`)
