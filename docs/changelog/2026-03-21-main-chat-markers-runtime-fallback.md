## 2026-03-21

## Modifiche
- aggiunta una guardia esplicita su `ReviewCoreBridge.isEnabled` in [ChatStore+RustBridge.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift) prima di invocare il boundary Rust dei markers
- mantenuta la logica markers in Rust quando il runtime e' disponibile, ma resa sicura la degradazione quando il review core e' forzato off o differito
- evitata ogni assertion su `stripCoderideMarkers(...)` e `extractLastOperationalThinkingLine(...)` nei path di bootstrap test/debug

## Test
- aggiunte regressioni in [ChatStoreRustBootstrapPolicyTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests.swift) per il bootstrap deferito con runtime Rust disabilitato

## Validazione
- verde:
  - `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreRustBootstrapPolicyTests -only-testing:SoloCodeAppTests/ChatStoreMarkerSanitizationTests`

## Rischio controllato
- nessuna regex markers reintrodotta in Swift
- la degradazione sicura resta confinata al bridge quando il runtime Rust non e' disponibile
