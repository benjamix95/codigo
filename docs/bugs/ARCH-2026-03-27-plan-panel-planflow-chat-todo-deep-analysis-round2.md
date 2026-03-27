# Deep Analysis Round 2 — Plan / Panel / PlanFlow / Chat / Todo

**Data**: 2026-03-27
**Scope**: secondo audit sui flussi `Plan`, `PlanPanel`, `PlanFlow`, chat e todo dopo la remediation precedente
**Tipo**: analisi read-only, nessuna modifica runtime applicata in questo pass

---

## Executive summary

Il primo fix ha ridotto i path piu' caldi su query todo e invalidazioni chat. Nel secondo pass emergono soprattutto:

1. **duplicazioni di consumo eventi** nei job pipeline raw
2. **restore di stato incoerente** su thread build-agent
3. **refresh/sync duplicati** tra chat UI e runtime bridge
4. **query recent-first invece di scope-first** che possono nascondere dati reali del thread corrente
5. **persistenza trace ancora costosa** su flussi rumorosi

---

## BOTTLENECK-R2-01 — Raw pipeline events possono essere consumati due volte

**Priorita'**: P1
**Tipo**: bug logico + bottleneck
**File**:
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents.swift`

**Evidenza**
- Nei job `agentPipeline`, `executeSendMessageTurn` installa `rawEventHandler` che chiama `handleRawStreamEvent(...)` in [ChatPanelView+PartL_SendMessageExecution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift#L139).
- `PipelineIntegrationService.handleRawEvent` richiama sempre prima `currentRuntime?.rawEventHandler` e poi continua col proprio raw path locale in [PipelineIntegrationService+EventSupport.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift#L17).
- Solo il ramo debug ha una guardia esplicita contro la doppia applicazione (`if currentRuntime?.rawEventHandler == nil`) in [PipelineIntegrationService+EventSupport.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift#L38).
- `handleRawStreamEvent` entra poi in `recordTaskActivity(...)`, che aggiunge envelope, activity e side effects su todo/plan in [ChatPanelView+PartP_Streaming2.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_Streaming2.swift#L7) e [ChatPanelView+PartF_DebugTodoEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoEvents.swift#L93).

**Problema**
- Per eventi `todo_write`, `plan_*` e in generale envelope non-debug, il callback UI puo' gia' applicare il side effect e poi il raw path interno lo riapplica o duplica almeno la `TaskActivity`.
- Il commento in `handleRawEvent` riconosce il problema solo per debug, ma il pattern e' strutturalmente identico anche per gli altri eventi.

**Impatto**
- doppie `TaskActivity`
- possibile doppio avanzamento todo/runtime
- sync plan board ridondanti
- piu' I/O e piu' invalidazioni UI del necessario

**Direzione fix**
- scegliere una sola source of truth per il consumo raw nei job pipeline:
  - o callback UI
  - o raw path interno
- mantenere il raw path locale solo come fallback quando `rawEventHandler == nil`

---

## BOTTLENECK-R2-02 — Restore di stato errato sulla conversazione build-agent

**Priorita'**: P1
**Tipo**: bug di stato / thread switch
**File**:
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlow.swift`

**Evidenza**
- `restorePlanStateIfNeeded` forza `planFlowPhase = .building` solo se `activeBuildPlanConversationId == conversationId` in [ChatPanelView+PartB_ComposerUI.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift#L141).
- Subito dopo, per ogni altra conversazione build-scoped, ritorna senza riallineare `phase/state` in [ChatPanelView+PartB_ComposerUI.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift#L148).
- Ma `isPlanBuildContext(...)` considera build-scoped anche `activeBuildAgentConversationId` in [ChatPanelSupport+PlanFlow.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPlan/ChatPanelSupport+PlanFlow.swift#L55).

**Problema**
- Se l’utente passa al thread dell’agent worker durante un build attivo, il flow lo considera “contesto build”, ma il restore non imposta `.building`.
- Il panel puo' quindi restare con stato precedente o `idle`, pur essendo dentro una conversazione che partecipa al build.

**Impatto**
- UI incoerente tra plan thread e worker thread
- indicatori build/plan panel non affidabili dopo switch conversazione
- rischio di mostrare contenuto stale o controlli sbagliati

**Direzione fix**
- distinguere esplicitamente:
  - plan conversation owner
  - build agent conversation
- ripristinare almeno uno stato coerente (`.building` o stato dedicato) anche per `activeBuildAgentConversationId`

---

## BOTTLENECK-R2-03 — Apertura del Plan Panel invia due volte `set_plan_panel_visible`

**Priorita'**: P2
**Tipo**: bug/bottleneck di bridging
**File**:
- `App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift`
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift`

**Evidenza**
- `openPlanPanelForCurrentContext()` setta `showPlanPanel` e chiama subito `syncPlanPanelVisibilityToRust(true)` in [ChatPanelView+PartB_ComposerUI.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatComposer/ChatBindings/ChatPanelView+PartB_ComposerUI.swift#L186).
- L’`onChange` di `showPlanPanel` richiama a sua volta `syncPlanPanelVisibilityToRust(isOpen)` in [ChatPanelView+LifecycleModifiers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+LifecycleModifiers.swift#L151).

**Problema**
- Ogni open del panel emette lo stesso intent verso il bridge due volte.

**Impatto**
- churn inutile sul bridge Rust/UI
- possibile doppio side effect su runtime snapshot / visible state
- rumore evitabile nei path di apertura automatica

**Direzione fix**
- lasciare il sync solo nell’`onChange(showPlanPanel)` oppure solo nell’API di open, non in entrambi

---

## BOTTLENECK-R2-04 — Refresh della chat sovrapposti per lo stesso evento logico

**Priorita'**: P2
**Tipo**: bottleneck UI
**File**:
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift`

**Evidenza**
- `streamContentVersion` fa `refreshMessagesSnapshot()` immediato in [ChatPanelView+PartC_MessageAreaRefreshModifiers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageAreaRefreshModifiers.swift#L13).
- `chatStore.objectWillChange` pianifica un altro refresh in [ChatPanelView+PartC_MessageHeader.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift#L264).
- `pipelineIntegrationService.snapshotDidChangePublisher` pianifica refresh due volte nello stesso handler, una immediata e una in `DispatchQueue.main.async` in [ChatPanelView+PartC_MessageHeader.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift#L268).
- Molti handler `plan_*` mutano `chatStore` e poi incrementano `streamContentVersion`, ad esempio [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L200) e [ChatPanelView+PartF_PlanEvents.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift#L249).

**Problema**
- Lo stesso evento plan/todo puo' causare 2-3 refresh della stessa snapshot messaggi.

**Impatto**
- lavoro ridondante sul main thread
- piu' rischio di jank durante streaming e panel transitions
- maggiore fragilita' nei race window gia' mitigate con safety net

**Direzione fix**
- consolidare le fonti di refresh
- trasformare `refreshMessagesSnapshot()` in refresh coalesciato per tick
- evitare refresh extra quando una mutazione ha gia' invalidato via `chatStore.objectWillChange`

---

## BOTTLENECK-R2-05 — La trace del Plan Panel puo' sparire se altri thread sono piu' rumorosi

**Priorita'**: P2
**Tipo**: bug di query/scoping
**File**:
- `App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+ScopedQueries.swift`

**Evidenza**
- `PlanPanelView.planTraceActivities` prende `taskActivityStore.planRelevantRecentActivities(limit: 120)` e poi filtra per conversazione in [PlanPanelView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/PlanPanel/PlanPanelView.swift#L71).
- `planRelevantRecentActivities(limit:)` fa prima `recentActivities(limit:)` e poi filtra i tipi in [TaskActivityStore+Query.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift#L188).
- Anche la versione “scoped” prende prima il recente globale e solo dopo filtra per conversation in [TaskActivityStore+ScopedQueries.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+ScopedQueries.swift#L21).

**Problema**
- Se altri thread generano molte activity dopo il thread corrente, gli ultimi 120 eventi globali possono non contenere piu' quelli della conversazione che il panel sta mostrando.

**Impatto**
- panel trace incompleta o vuota anche quando il thread corrente ha ancora trace rilevante
- debug piu' difficile su sessioni multi-thread/multi-agent

**Direzione fix**
- applicare prima lo scope conversazione e poi il limit
- oppure mantenere un indice recent-per-conversation

---

## BOTTLENECK-R2-06 — `ToolTraceStore.append` fa sort completo e write a disco per ogni evento

**Priorita'**: P2
**Tipo**: bottleneck persistenza/trace
**File**:
- `App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift`

**Evidenza**
- Ogni `append(event:)` rilegge la cache del turn, appende, fa `events.sort`, invalida cache di conversazione e poi encoda/scrive l’evento a disco in [ToolTraceStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift#L165).
- Il write e' per-event, non batchato, in [ToolTraceStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift#L177) e [ToolTraceStore.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift#L305).

**Problema**
- Sul path caldo di trace:
  - sort O(n log n) a ogni append
  - encode per-event
  - write NDJSON per-event

**Impatto**
- costo cumulativo alto su task/tool rumorosi
- degrada panel trace, message trace e summary dei file change

**Direzione fix**
- assumere monotonicita' di `sequence/timestamp` e appendere senza resort completo nei casi normali
- batchare encode/write su finestra corta
- spostare il ricalcolo summary/file-change fuori dal turn hot path

---

## Riepilogo Priorita'

| Priorita' | ID | Area | Impatto principale |
|----------|----|------|--------------------|
| P1 | BOTTLENECK-R2-01 | Raw pipeline event routing | duplicazioni di state/activity |
| P1 | BOTTLENECK-R2-02 | Restore build-agent thread | stato plan incoerente su switch |
| P2 | BOTTLENECK-R2-03 | Panel visibility bridge | doppio intent verso Rust |
| P2 | BOTTLENECK-R2-04 | Chat snapshot refresh | refresh ridondanti |
| P2 | BOTTLENECK-R2-05 | Plan trace scoping | trace del thread corrente tronca |
| P2 | BOTTLENECK-R2-06 | ToolTrace persistence | costo per-event troppo alto |

---

## Ordine consigliato di intervento

1. bloccare la doppia applicazione eventi nel raw pipeline
2. correggere il restore della build-agent conversation
3. rimuovere i doppi sync e i refresh sovrapposti
4. sistemare query trace scope-first
5. solo dopo: ottimizzare la persistenza del `ToolTraceStore`
