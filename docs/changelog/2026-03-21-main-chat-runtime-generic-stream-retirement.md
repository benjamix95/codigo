# 2026-03-21 main chat runtime generic stream retirement

## Summary
- rimosso dal path runtime della main chat il generic stream runner Swift legacy del `ConversationFlowCoordinator`
- aggiornati i test del coordinator per validare il polling Rust-only
- riordinato `DebugPipeline` in file separati sotto soglia invece di lasciare un file monolitico
- assorbito il piccolo shell `GitService.swift` dentro `GitService+Sync.swift` per lasciare il worktree coerente e il tranche gate senza detriti Swift aggiuntivi

## Changes
- `ConversationFlowCoordinator+Support.swift`
  - eliminati helper e reducer del generic stream legacy non piu' usati dal path Rust-only
- `WorkspaceStore+ProjectContextSync.swift`
  - il ramo non-`MainChatRustTransportProvider` del runtime main chat ora fallisce in modo chiuso
- `ConversationFlowCoordinatorTests.swift`
  - i test di stream usano provider Rust transport simulato invece del vecchio mock generic stream
- `ChatPanelView+DebugPipelineIntents.swift`
  - mantiene gli intent della sessione debug e il request builder in un file dedicato sotto soglia
- `ChatPanelView+DebugPipelineNativeIntents.swift`
  - mantiene solo i comandi native-specific
- `DebugProjectionEventConsumer.swift`
  - spostato sotto `Services/Debug` per allinearlo al suo ruolo reale di projection glue fuori dal dominio `Runtime`
- `GitService+Sync.swift`
  - incorpora il piccolo shell `GitService`
- `GitService.swift`
  - rimosso dopo l'assorbimento nel file sync
- `project.pbxproj`
  - registrato il nuovo file runtime e rimosse le referenze al file debug intents eliminato

## Validation
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/WorktreeMergeAIServiceTests -only-testing:SoloCodeAppTests/GitServiceTests`
- `./scripts/validate_rust_cutover_boundary.sh --workspace '/Users/benjaminstoica/SoloCode' --files 'App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift,App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/ChatPanelView+DebugPipelineIntents.swift,App/SoloCodeApp/Sources/Runtime/DebugPipeline/ChatPanelView+DebugPipelineNativeIntents.swift,App/SoloCodeApp/Sources/Git/Services/GitService+Sync.swift,App/SoloCodeApp/Sources/Git/Services/GitService.swift,Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift,Solo Code.xcodeproj/project.pbxproj'`
