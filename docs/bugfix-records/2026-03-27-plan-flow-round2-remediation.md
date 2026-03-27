# Plan / Chat / Todo Round 2 Remediation — 2026-03-27

## Bug Fix Record
- Categoria: A/B
- Bug: il secondo audit aveva evidenziato duplicazioni di consumo eventi raw pipeline, restore incoerente sul build-agent thread, sync duplicati del plan panel, query trace non scope-first e costo eccessivo sul path di persistenza del `ToolTraceStore`.
- Sintomo:
  1. rischio di doppia applicazione per eventi `todo_*` / `plan_*` quando era presente `rawEventHandler`
  2. stato plan incoerente dopo switch sul thread worker del build
  3. doppio sync `set_plan_panel_visible`
  4. trace del Plan Panel troncata da activity di altri thread
  5. resort completo dei trace event a ogni append
- Impatto:
  - possibile drift di stato tra pipeline runtime, chat e plan panel
  - duplicazione di side effect e task activity
  - perdita di osservabilita' nel panel del thread corrente
  - costo superfluo sul path caldo dei trace
- Gravita': alta
- Causa probabile:
  - ownership non chiara tra callback raw UI e raw path interno del pipeline runtime
  - restore state centrato solo sul thread plan owner, non sul build agent
  - limit applicato prima dello scope nelle query delle activity plan
  - `ToolTraceStore` pensato per correttezza, non per alto throughput
- Scope consentito:
  - pipeline raw event routing
  - helper del plan flow
  - restore/open panel logic
  - query scoped activity
  - `ToolTraceStore`
  - test di regressione
- Non-scope:
  - refactor completo del `PlanFlow`
  - redesign panel o chat timeline
  - cambi architetturali al bridge Rust
- Moduli confinanti da verificare:
  - `PipelineIntegrationServiceTests`
  - `PlanShortcutAndCommandTests`
  - `TaskActivityStoreScopedActivitiesTests`
  - `ToolTraceStoreTests`
- Test da aggiungere o aggiornare:
  - raw callback ownership per `todo_write`
  - restore phase per build-agent conversation
  - routing plan stream quando il gate e' spento
  - plan relevant activity scope-first
- Strategia di fix minimo:
  1. bloccare il raw path locale quando un external raw handler possiede gia' gli effetti UI
  2. introdurre helper puro per il restore `.building` su plan/build conversations
  3. evitare il doppio sync del panel visibility
  4. applicare scope conversazione prima del `limit` nella trace plan
  5. togliere il full sort dal path normale di append del `ToolTraceStore`
  6. batchare gli append su disco del trace store su finestra corta
- Verifica post-fix:
  - `xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests -only-testing:SoloCodeAppTests/TaskActivityStoreScopedActivitiesTests -only-testing:SoloCodeAppTests/ToolTraceStoreTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests`
- Commit previsto:
  - fix(plan): resolve second-pass flow bottlenecks

## Fix applicati

### P1 — ownership chiara per gli eventi raw pipeline
- `PipelineIntegrationService.handleRawEvent` non applica piu' localmente i side effect `todo/plan/debug/activity` quando esiste gia' un `rawEventHandler` esterno che possiede il consumo UI.
- `assistant_update` e gli artifact pipeline restano comunque proiettati dove serve.

### P1 — restore corretto sul build-agent thread
- introdotto helper `restoredPlanBuildPhase(...)` e usato nel restore del panel state.
- anche la conversazione `activeBuildAgentConversationId` viene ora riallineata a `.building`.

### P2 — rimosso doppio sync panel visibility
- `openPlanPanelForCurrentContext` non forza piu' direttamente `syncPlanPanelVisibilityToRust(true)`.
- la visibilita' e' sincronizzata da un solo punto: l'`onChange(showPlanPanel)`.

### P2 — trace plan scope-first
- `TaskActivityStore.planRelevantRecentActivities(limit:conversationId:)` applica ora prima lo scope di conversazione e solo dopo il `limit`.
- `PlanPanelView` usa direttamente la query scoped, senza filtro globale successivo.

### P2 — hot path `ToolTraceStore` alleggerito
- nel caso normale gli eventi vengono appesi senza resort completo se l'ordine e' gia' monotono.
- la persistenza del trace usa un buffer breve su `diskQueue` invece del write immediato per ogni evento.
