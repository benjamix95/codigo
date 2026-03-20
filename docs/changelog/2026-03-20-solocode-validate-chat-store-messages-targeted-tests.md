## 2026-03-20

- aggiunta una regola dedicata in [solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate) per `Chat/Support/StoreProjection/Messages/*`
- il validator ora seleziona:
  - `SoloCodeAppTests/ChatStoreStreamingTargetTests`
  - `SoloCodeAppTests/PipelineIntegrationServiceTests`
- per i file `StoreRust/*` mantiene anche `SoloCodeAppTests/ChatStoreTaskOwnershipTests`
- per `StoreProjection/Conversations/*` seleziona `SoloCodeAppTests/ChatStoreTaskOwnershipTests`
- aggiunto in allowlist [TaskStatusModifiers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/TaskStatus/TaskStatusModifiers.swift) come `ui_view` per allineare il gate a un file puramente presentation-only
- aggiunto in allowlist [PrimaryTextBlockView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Timeline/Blocks/PrimaryTextBlockView.swift) come `ui_view` per allineare il gate a un altro file puramente presentation-only
- aggiunto in allowlist [ChatBackgroundStyle.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/ChatBackgroundStyle.swift) come `ui_view` per allineare il gate a una configurazione puramente presentation-only
- aggiunto in allowlist [TraceSummaryCardView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Timeline/Blocks/TraceSummaryCardView.swift) come `ui_view` per allineare il gate a un'altra card puramente presentation-only
- evitato il fallback all'intera suite `SoloCodeAppTests` per modifiche confinate allo store messages della `main chat`
