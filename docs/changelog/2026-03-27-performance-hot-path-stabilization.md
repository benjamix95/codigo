# Changelog — 2026-03-27 Performance Hot Path Stabilization

## UI / Chat root

- Rimossi observer passivi dai wrapper root in `ChatPanelView+RootLayout`.
- `ChatPanelView` ora cache-a anche:
  - activity snapshot per la strip root
  - snapshot pipeline per conversation
- `TaskControlBar` e `SwarmProgressView` ricevono dati già derivati invece di osservare direttamente `PipelineIntegrationService` o store più larghi.
- `ChatPanelView+PartC_MessageHeader` usa ora un publisher pipeline mirato per conversation invece di ascoltare il broadcast globale del servizio.

## Pipeline

- Aggiunto `snapshotDidChange` in `PipelineIntegrationService` con helper `snapshotDidChangePublisher(for:)`.
- I flush snapshot notificano solo la conversation effettivamente toccata.
- Aggiunti test di regressione in `PipelineIntegrationSnapshotPublisherTests`.

## Todo

- `TodoStore.saveTodos()` mantiene la persistenza `UserDefaults` immediata ma debounce-a la sync verso `MCPSharedState`.
- `syncToSharedState()` continua a forzare un flush immediato quando richiesto esplicitamente.

## EventBus

- Estratto lifecycle/idempotency in `EventBus+Lifecycle.swift`, riportando `EventBus.swift` sotto il limite locale.
- Ridotto l'overhead di prune nel publish path senza cambiare il contratto pubblico.
- Corretto il pruning per non introdurre eviction anticipata su capacità piccole.

## Verifica

- App tests:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotTests -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotPublisherTests -only-testing:SoloCodeAppTests/TodoStorePersistenceTests`
- Engine tests:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/EventBusTests -only-testing:CoderEngineTests/AgentWorkerEventBridgeTests`
