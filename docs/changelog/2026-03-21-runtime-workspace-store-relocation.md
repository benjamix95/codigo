# 2026-03-21 runtime workspace store relocation

## Summary
- spostato fuori da `Runtime` l'ultimo residuo legacy del prefisso: `WorkspaceStore`
- spezzato il file in moduli sotto soglia senza cambiare la logica

## Changes
- `App/SoloCodeApp/Sources/Services/Project/WorkspaceStore.swift`
  - stato principale e lifecycle dell'indicizzazione
- `App/SoloCodeApp/Sources/Services/Project/WorkspaceStore+Workspaces.swift`
  - mutazioni del workspace e sync con `ProjectContext`
- `App/SoloCodeApp/Sources/Services/Project/WorkspaceStore+Paths.swift`
  - normalizzazione path, esclusioni e helper debug
- `Solo Code.xcodeproj/project.pbxproj`
  - aggiornati i file di build sul nuovo percorso
- `Config/validation/rust-cutover-swift-allowlist.txt`
  - aggiunta allowlist per `Services/Project/WorkspaceStore*.swift` come infrastruttura project/indexing fuori dal dominio runtime main-chat

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/WorkspaceStorePathNormalizationTests -only-testing:SoloCodeAppTests/WorkspaceStoreContextSyncTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Runtime/WorkspaceStore.swift,App/SoloCodeApp/Sources/Services/Project/WorkspaceStore.swift,App/SoloCodeApp/Sources/Services/Project/WorkspaceStore+Workspaces.swift,App/SoloCodeApp/Sources/Services/Project/WorkspaceStore+Paths.swift,Config/validation/rust-cutover-swift-allowlist.txt,Solo Code.xcodeproj/project.pbxproj'`
