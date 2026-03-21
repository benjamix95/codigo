## 2026-03-21

## Modifiche
- ripristinato in [ChatPanelView+PartL_SendMessageExecution.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatSend/Runtime/ChatPanelView+PartL_SendMessageExecution.swift) un routing esplicito del send della main chat:
  - `planFlow` per i turni plan multi-step
  - `agentPipeline` quando `coderMode == .agent` e il provider runtime non usa il trasporto Rust
  - `standardStream` solo per il path diretto Rust-backed
- evitato il passaggio del provider Swift fallback nel coordinator `runStream` Rust-only, che causava l'interruzione immediata del turno

## Test
- aggiunti test in [RustMainChatProviderFactoryTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/RustMainChatProviderFactoryTests.swift) per verificare:
  - fallback al pipeline path in modalità `Agent` quando il provider non usa Rust
  - mantenimento del path standard quando il trasporto Rust è disponibile
  - priorità del plan flow sul trasporto provider

## Validazione
- da eseguire:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests`

## Rischio controllato
- nessuna modifica al bootstrap della dylib Rust
- nessun refactor del `ConversationFlowCoordinator`
- fix confinato al decision point del send path agent
