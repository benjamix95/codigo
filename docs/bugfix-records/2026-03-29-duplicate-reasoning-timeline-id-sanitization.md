# Bugfix Record — 2026-03-29

## Scope
- Eliminare i warning `ForEach ... seg-reason-reasoning occurs multiple times`.
- Rendere più robusti snapshot/persistence contro blocchi timeline con ID duplicate.

## Modifiche
- Aggiunto helper [`ChatTimelineBlockIdentitySanitizer.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Models/ChatTimelineBlockIdentitySanitizer.swift) che rende univoci gli `id` duplicati dei blocchi timeline mantenendo ordine e `sequence`.
- Applicato il sanitizer in [`ChatStoreMessageModels+Pipeline.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStore/Models/ChatStoreMessageModels+Pipeline.swift) e [`ChatTurnState.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatPipeline/Projection/Core/ChatTurnState.swift).
- Aggiunta ulteriore difesa in [`ChatTurnInterleavedSegment.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInterleavedSegment.swift), includendo la `sequence` nell’identità del segmento reasoning.

## Test
- [`ChatTimelineBlockIdentitySanitizerTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatTimelineBlockIdentitySanitizerTests.swift)
- [`ChatStorePipelineInterleavingPersistenceTests.swift`](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStorePipelineInterleavingPersistenceTests.swift)

## Rischi controllati
- Nessun cambio all’ordering cronologico della timeline.
- Nessun cambio al contenuto dei blocchi reasoning.
- Solo correzione dell’identità dei blocchi e hardening dei consumer snapshot/persistence.
