# Bug Fix Record
- Categoria: C
- Bug: la shell-state del boundary UI della main chat veniva ancora ricostruita in più binding Swift distinti (`stream`, `plan`, `auto-todo`) con varianti locali.
- Sintomo: `RustMainChatStoreAdapter.uiState(...)` veniva chiamato da più file con combinazioni quasi identiche di `runtimeSnapshot`, `selectedConversationId`, `draftText`, `planPanelVisible`, `followLive`, `collapsedArtifactIdsByTurn` e talvolta `autoTodoRuntimeStateByMessage`.
- Impatto: rischio di divergenze di projection tra call-site diversi, difficile da rilevare perché il core Rust riceveva input formalmente validi ma non sempre costruiti nello stesso modo.
- Gravità: bassa
- Steps to reproduce:
  1. Cercare `RustMainChatStoreAdapter.uiState(` nei binding chat.
  2. Confrontare `ChatPanelView+PartQ_Finalizers.swift`, `ChatPanelView+PartO_PlanPromptBuilders.swift` e `ChatPanelView+PartF_AutoTodoRuntime.swift`.
  3. Verificare che ogni file ricomponga a mano lo stesso boundary state con piccole varianti locali.
- Risultato attuale: il boundary UI Rust-backed dipendeva ancora da ricostruzioni Swift duplicate.
- Risultato atteso: i principali path Rust-backed della main chat devono costruire lo stato boundary in un unico punto condiviso.
- Causa probabile: il cutover Rust aveva già centralizzato reducer/store/runtime ma non il lato host che prepara lo stato UI per projection e intent.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_AutoTodoRuntime.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStreaming/Bindings/ChatPanelView+PartQ_Finalizers.swift`
  - `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PartO_PlanPromptBuilders.swift`
- Non-scope:
  - reducer/store/runtime Rust
  - `ToolEnabledLLMProvider`
  - send runtime con modifiche locali non verificate
- Moduli confinanti da verificare:
  - `RustMainChatUIBoundaryTests`
  - `RustMainChatUIBoundaryPlanTests`
  - `RustMainChatAutoTodoBoundaryTests`
- Test da aggiungere o aggiornare:
  - nessun nuovo test logico: le suite boundary esistenti coprono già i tre percorsi dopo la centralizzazione
- Strategia di fix minimo:
  - introdurre helper condivisi in `ChatPanelView` per risolvere `runtimeSnapshot`, costruire `MainChatUIStateBridge`, applicare intent e proiettare snapshot
  - far convergere `stream`, `plan` e `auto-todo` su quel punto unico
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryPlanTests -only-testing:SoloCodeAppTests/RustMainChatAutoTodoBoundaryTests`
- Commit previsto: `refactor(chat): centralize main chat ui boundary state`
