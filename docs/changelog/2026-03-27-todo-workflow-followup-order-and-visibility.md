# Changelog — 2026-03-27 — Todo workflow follow-up/order/visibility

## Obiettivo

Stabilizzare il workflow todo per evitare follow-up spuri, imporre l’ordine corretto dei task finali e mantenere visibili i completed nel composer overlay.

## Modifiche principali

### 1. Policy centralizzata per i follow-up finali

Aggiunto:
- `App/SoloCodeApp/Sources/Tasking/Support/TodoExecutionFollowUpPolicy.swift`

Cosa fa:
- normalizza le checklist di esecuzione;
- rimuove follow-up orfani o duplicati;
- riappende in ordine stabile i passi finali:
  1. `Code Review & Test`
  2. `Doc Writer`

### 2. Build del piano allineato alla nuova sequenza

Modificato:
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartK_PlanExecution.swift`

Cosa cambia:
- i todo del plan build vengono normalizzati prima di essere persistiti come canonical todos.

### 3. Rimozione dei follow-up review spuri

Modificati:
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartR_Tail.swift`

Cosa cambia:
- il pipeline recap finale non crea più un runtime todo review standalone;
- la finalizzazione di un turno con file edits non inietta più automaticamente un solo `Code Review & Test` fuori contesto.

### 4. Auto-completion più rigorosa e sequenziale

Modificato:
- `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`

Cosa cambia:
- viene sempre completato prima l’item realmente `inProgress`;
- il review step `pending` viene completato solo quando non esiste più lavoro esecutivo reale aperto;
- `Doc Writer` non viene saltato né promosso implicitamente fuori ordine.

### 5. Completed persistenti nel composer overlay

Modificato:
- `App/SoloCodeApp/Sources/ChatView/Composer/ComposerTodoOverlayView.swift`

Cosa cambia:
- l’overlay resta visibile anche quando tutti i todo reali sono `done`;
- i placeholder operativi restano esclusi;
- i completed continuano a mostrarsi con strikethrough nella checklist.

## Test aggiunti/aggiornati

Aggiunto:
- `Tests/SoloCodeAppTests/TodoExecutionFollowUpPolicyTests.swift`

Aggiornati:
- `Tests/SoloCodeAppTests/ComposerTodoOverlayStateTests.swift`
- `Tests/SoloCodeAppTests/ChatPanelTodoFinalizationTests.swift`
- `Tests/SoloCodeAppTests/PipelineIntegrationServiceTests.swift`

## Verifica eseguita

Comando usato:
- `xcodebuild test -project './Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:'SoloCodeAppTests/TodoExecutionFollowUpPolicyTests' -only-testing:'SoloCodeAppTests/ComposerTodoOverlayStateTests' -only-testing:'SoloCodeAppTests/ChatPanelTodoFinalizationTests' -only-testing:'SoloCodeAppTests/PipelineIntegrationServiceTests'`

Esito:
- `37 test`, `0 failure`
- `** TEST SUCCEEDED **`

## Note

In questa sessione `xcodebuildmcp` non era esposto nei tool live, quindi per i test macOS/Xcode ho usato il fallback diretto `xcodebuild`.