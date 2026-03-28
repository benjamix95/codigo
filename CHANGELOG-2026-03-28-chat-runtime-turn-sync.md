# Changelog - 2026-03-28 - Chat runtime turn sync

- Corretto il path live `stream_replace_text`: dopo il bridge UI Rust la chat sincronizza di nuovo `runtimeSnapshot.turnState` dentro `conversationRuntime`.
- Questo evita che il renderer cada nel caso `no_pipeline_turn` mentre arrivano tool trace e testo nello stesso turno assistant.
- Aggiunto un helper dedicato per estrarre in modo sicuro il `ChatTurnState` dal `MainChatUIIntentResponseBridge`.
- Aggiunta una regressione che verifica l'estrazione del turn state runtime per la conversazione corretta.
- File toccati:
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_StreamApply.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_StreamRuntimeSync.swift`
  - `Tests/SoloCodeAppTests/MainChatUIIntentRuntimeSyncTests.swift`
