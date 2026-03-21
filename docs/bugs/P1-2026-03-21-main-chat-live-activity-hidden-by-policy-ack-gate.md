# Bug Fix Record
- Categoria: A
- Bug: il gate UI `policy_ack` può nascondere completamente gli eventi live della chat mettendoli in coda prima di qualunque side effect locale.
- Sintomo: footer/feed live vuoti o quasi vuoti con provider diversi, mentre il task continua a lavorare; restano visibili solo eventi generici come `Thinking`.
- Impatto: l’utente perde il feedback operativo in tempo reale e interpreta il task come bloccato.
- Gravità: alta
- Steps to reproduce:
  1. Avviare una chat con `agentsHardBlockEnabled = true`.
  2. Usare un provider che non emette `policy_ack` in anticipo oppure lo emette tardi.
  3. Inviare raw events operativi (`assistant_update`, `command_execution`, `agent`, `web_search_*`, `mcp_tool_call`).
  4. Verificare che `handleRawStreamEvent(...)` li metta in `policyAckBlockedQueue` e ritorni prima di `recordTaskActivity(...)`.
- Risultato attuale: gli eventi live provider-agnostic vengono accodati e quindi non alimentano feed/status/footer finché l’ack non arriva; se l’ack non arriva, la UI non mostra più nulla di concreto.
- Risultato atteso: il gate `policy_ack` non deve oscurare gli eventi di telemetria/live già osservabili; il feedback operativo deve restare visibile anche se l’enforcement lato provider segnala assenza di ack.
- Causa probabile: il gate UI usa `requiresPolicyAck(...)` con perimetro troppo ampio e applica un `return` anticipato prima di ogni side effect di visibilità.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
  - `Tests/SoloCodeAppTests/ToolTraceVisibilityTests.swift`
  - `docs/bugs/**`
  - `docs/changelog/**`
- Non-scope:
  - parser provider
  - reducer/store main chat
  - rendering timeline dei messaggi
  - enforcement provider-side del tool protocol
- Moduli confinanti da verificare:
  - `ChatPanelView+PartP_Streaming2`
  - `ToolTraceVisibility`
  - `TaskActivityStore+Visibility`
- Test da aggiungere o aggiornare:
  - bypass del gate per `assistant_update`, `command_execution`, `agent`, `web_search_*`, `mcp_tool_call`
  - regressione che mantenga il gate attivo per eventi sconosciuti/non-live
- Strategia di fix minimo:
  - introdurre un’esenzione esplicita per gli eventi live di visibilità nel gate `shouldHardBlockForMissingPolicyAck(...)`
  - non modificare l’enforcement upstream dei provider
- Verifica post-fix:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ToolTraceVisibilityTests -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests`
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatPipelineReducerTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
- Commit previsto: `fix(chat): keep live activity visible before policy ack`

