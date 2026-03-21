## 2026-03-21

## Modifiche
- aggiunto un bypass esplicito del gate UI `policy_ack` in [ChatPanelView+PartP_PolicyEnforcement.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift) per gli eventi live gia' osservabili (`assistant_update`, `command_execution`, `agent`, `web_search_*`, `mcp_tool_call`, ecc.)
- il gate continua a esistere per eventi sconosciuti/non-live, ma non puo' piu' oscurare il feedback operativo comune a tutti i provider

## Test
- aggiunti test in [ToolTraceVisibilityTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ToolTraceVisibilityTests.swift) per:
  - bypass del gate su eventi live operativi
  - mantenimento del gate su eventi custom non riconosciuti

## Validazione
- da eseguire:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`

## Rischio controllato
- nessuna modifica al parser provider
- nessuna modifica al contenuto dei messaggi assistant
- fix confinato alla visibilita' live della UI e ai test di policy correlati
