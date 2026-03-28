# Changelog - 2026-03-28 - Chat pipeline snapshot refresh fan-out reduction

- Ridotto il fan-out di refresh quando `PipelineIntegrationService.snapshotDidChangePublisher` notifica la chat UI.
- Il publisher pipeline continua a rinfrescare il chrome/runtime della chat, ma non schedula piu' un refresh completo dei messaggi in parallelo.
- Estratta la policy in `ChatPanelPipelineSnapshotRefreshPlan` per rendere esplicito il contratto e testarlo in modo diretto.
- Aggiunta una regressione dedicata per documentare che il refresh messaggi rimane disaccoppiato dai cambi snapshot della pipeline.
- Perimetro toccato:
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefreshPolicy.swift`
  - `Tests/SoloCodeAppTests/ChatPanelPipelineSnapshotRefreshPolicyTests.swift`
- Rischio residuo:
  - il root `ChatPanelView` resta molto ampio e continua a osservare diversi store; questo fix riduce un fan-out specifico, ma non risolve da solo l'intero dependency graph.
