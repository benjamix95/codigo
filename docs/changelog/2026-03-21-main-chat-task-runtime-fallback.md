# 2026-03-21 - Main chat task runtime fallback

## Cosa cambia
- documentato il bug in [P1-2026-03-21-main-chat-begin-task-crashed-when-rust-task-runtime-was-unavailable.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-21-main-chat-begin-task-crashed-when-rust-task-runtime-was-unavailable.md)
- il bridge `ChatStore+RustBridge` usa il fallback task runtime Swift anche quando il runtime Rust non risponde nel percorso app-side
- `beginTask`, `endTask` e `setTaskStatus` non fanno più crashare la main chat per `begin_task` non disponibile
- aggiunta regressione dedicata in `ChatStoreTaskOwnershipTests` sul caso `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `Tests/SoloCodeAppTests/ChatStoreTaskOwnershipTests.swift`

## Verifica
- `xcodebuild test -project "Solo Code.xcodeproj" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatStoreTaskOwnershipTests`

## Note
- fix confinato al boundary Swift del task runtime main chat
- nessuna modifica al runtime Rust sottostante
