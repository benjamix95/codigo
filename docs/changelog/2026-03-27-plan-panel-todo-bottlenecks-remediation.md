# Changelog — 2026-03-27 — Remediation Plan Panel / Todo Bottlenecks

## Cosa e' stato fatto

- Ottimizzata la policy di visibilita' dei todo in chat con uno snapshot condiviso.
- Introdotto batching esplicito nel `TodoStore` per evitare full-save ripetuti nello stesso evento.
- Coalesciata la sincronizzazione `canonical todo -> plan board` nei path bulk del plan.
- Rimossa l'invalidazione della timeline chat per `todo_read`.
- Eliminato un prepare ridondante nel passaggio `PlanFlow` phase2 -> phase3.
- Ridotto churn inutile nel `PlanPanel` evitando update della cache auth invariata.

## File principali toccati

- `App/SoloCodeApp/Sources/Tasking/Policy/TodoChatDisplayPolicy.swift`
- `App/SoloCodeApp/Sources/Tasking/Policy/TodoChatDisplayScopeSnapshot.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TodoStore+MutationBatching.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_TodoEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_PlanEvents.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+TodoRawEventSupport.swift`

## Test eseguiti

- `xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TodoStoreTests -only-testing:SoloCodeAppTests/TodoStorePersistenceTests -only-testing:SoloCodeAppTests/TodoChatDisplayPolicyTests -only-testing:SoloCodeAppTests/TodoStoreMutationBatchingTests -only-testing:SoloCodeAppTests/TodoChatDisplayScopeSnapshotTests -only-testing:SoloCodeAppTests/ChatTimelineInvalidationPolicyTests -only-testing:SoloCodeAppTests/ChatTodoVisibilityTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`

## Esito

- 101 test eseguiti
- 0 failure
- remediation applicata senza toccare le altre modifiche locali presenti nel workspace
