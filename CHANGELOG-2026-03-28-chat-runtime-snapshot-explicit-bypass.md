# Changelog

## 2026-03-28

### Fix
- corretto il wiring di `currentMainChatUIBridgeContext(...)` perché anche gli snapshot runtime espliciti passino dalla preferenza verso `conversationRuntime` quando quest'ultimo ha una timeline più ricca
- estratti in `/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_RuntimeSnapshotPreference.swift` gli helper di scelta snapshot, inclusa una funzione pura riusabile nei test
- spostati nello stesso file gli helper `resolvedMainChatRuntimeSnapshot(...)` e `runtimeSnapshotForPlanUIIntent(...)` per tenere il file runtime toccato sotto la soglia operativa

### Test
- aggiunti test in `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/MainChatRuntimeSnapshotPreferenceTests.swift` per:
  - sostituzione di uno snapshot esplicito più povero con il `conversationRuntime` più ricco
  - creazione di uno snapshot agent quando manca il base snapshot

### Evidenze
- i log mostravano `merge_uses_conversation_runtime_not_integration` con molti marker tool disponibili
- lo stesso path continuava però a produrre messaggi con testo principale dominante, coerente con una risincronizzazione da snapshot esplicito più povero durante `stream_replace_text`
