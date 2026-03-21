## 2026-03-21

## Modifiche
- aggiunto un guard esplicito in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift) per non invocare `chat_core_markers_handle` quando `ReviewCoreBridge.isEnabled` e' falso
- mantenuto il dominio markers interamente in Rust: nessuna regex o extraction legacy e' stata reintrodotta in Swift
- trasformato il path di indisponibilita' del runtime in fallback sicuro:
  - `stripCoderideMarkers(...)` restituisce il contenuto safe gia' previsto dal bridge
  - `extractLastOperationalThinkingLine(...)` restituisce `nil`

## Test
- aggiunte regressioni in [ChatStoreRustBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift) per verificare che il bridge markers non crashi quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## Obiettivo
- evitare crash nel bootstrap e nei test app-side quando il review core Rust e' differito
- preservare la migrazione completa della logica markers in Rust quando il runtime e' disponibile
