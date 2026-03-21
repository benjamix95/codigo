# 2026-03-21 - Main chat store bridge fallback for visible messages

## Cosa cambia
- documentato il bug in [P1-2026-03-21-main-chat-send-succeeded-but-rust-store-bridge-dropped-visible-messages.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-main-chat-send-succeeded-but-rust-store-bridge-dropped-visible-messages.md)
- il `ChatStore` applica fallback locali per le mutazioni chat fondamentali quando il bridge store Rust non risponde
- il submit della main chat mostra di nuovo messaggio utente e contenuto assistant anche con `ReviewCoreBridge` disabilitato
- aggiunte regressioni dedicate su `addMessage` e `updateLastAssistantMessage` in modalità fallback

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `Tests/SoloCodeAppTests/ChatStoreStreamingTargetTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreStreamingTargetTests -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`

## Note
- fix confinato al boundary store Swift/Rust della main chat
- nessuna modifica al runtime provider o alla pipeline CLI
