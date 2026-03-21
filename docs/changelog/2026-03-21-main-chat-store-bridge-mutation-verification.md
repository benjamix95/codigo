# 2026-03-21 - Main chat store bridge mutation verification

## Cosa cambia
- documentato il bug in [P1-2026-03-21-main-chat-store-bridge-could-ack-action-without-visible-mutation.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-main-chat-store-bridge-could-ack-action-without-visible-mutation.md)
- il `ChatStore` verifica ora che le mutazioni critiche siano realmente visibili dopo il passaggio nel boundary Rust
- se una mutazione non risulta osservabile, il bridge applica una correzione locale minima sullo stato della conversazione
- aggiunte regressioni mirate su `addMessage` e `updateLastAssistantMessage` per i casi di fallback

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`

## Note
- fix confinato al boundary store Swift/Rust della main chat
- mantiene il comportamento Rust-first ma ripara i no-op osservabili lato UI
