# 2026-03-23 chat inline policy ack

## Summary
- la chat ora riconosce i marker inline `[CODERIDE:policy_ack|hash=...]` nel testo streammato
- l’ack viene applicato allo stato policy prima che il testo venga ripulito per la UI
- gli eventi operativi accodati possono essere flushati senza generare falsi errori finali

## Changes
- `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartP_PolicyEnforcement.swift`
  - aggiunto parser per hash `policy_ack` inline
  - aggiunto consumo idempotente del marker inline con flush immediato della coda
- `App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift`
  - il callback `onText` processa i marker inline prima della sanitizzazione del testo
- `Tests/SoloCodeAppTests/ChatStreamFailureHandlingTests.swift`
  - aggiunti test sul parsing ordinato/deduplicato dei marker inline `policy_ack`

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests`
