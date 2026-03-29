# Changelog — 2026-03-29 — Pipeline raw envelope lazy normalization

## Sommario
Ridotto lavoro ridondante nel path caldo dei raw event pipeline senza cambiare il comportamento UI osservabile.

## Modifiche
- **`App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+EventSupport.swift`**
  - resa lazy la normalizzazione `EventNormalizer.normalizeEnvelope(...)` dentro `handleRawEvent`
  - la normalizzazione ora avviene solo quando serve davvero per debug projection o `TaskActivity`
  - i raw event con `rawEventHandler` esterno non costruiscono più envelope inutili
  - `show_task_panel`, `todo_write` e `plan_step` continuano a mantenere i side-effect necessari senza costo aggiuntivo di envelope
  - riuso del `streamId` già risolto nel projection path di `assistant_update`
- **`Tests/SoloCodeAppTests/PipelineIntegrationServiceTests.swift`**
  - aggiunta copertura per `show_task_panel` con `rawEventHandler` esterno: task status preservato, niente duplicazione `TaskActivity`
- **`Tests/CoderEngineTests/Pipeline/Bridge/AgentWorkerEventBridgeTests.swift`**
  - sincronizzata la raccolta degli `eventId` nel test concorrente del bridge per eliminare una flake da race del test harness
- **`Tests/CoderEngineTests/Pipeline/Bridge/AgentWorkerEventBridgeShutdownTests.swift`**
  - sincronizzata la raccolta di contatori/eventi nel test harness concorrente

## Impatto
- meno lavoro CPU/allocazioni sui raw event che vengono gestiti da callback esterne
- nessun cambiamento al contratto funzionale di `show_task_panel`, `assistant_update`, `todo_write` e `plan_step`

## Verifica
- test mirati `PipelineIntegrationServiceTests`
- test mirati `AgentWorkerEventBridgeTests`
