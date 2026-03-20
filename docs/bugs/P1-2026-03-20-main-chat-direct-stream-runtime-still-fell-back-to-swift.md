# P1 - Il direct stream della main chat ricadeva ancora su logica Swift locale

## Bug Fix Record
- Categoria: A
- Bug: il path `direct stream` della `main chat` continuava a dipendere da fallback Swift locale per la riduzione eventi e da un fallback completo `runStreamLegacy(...)` quando il runtime Rust non rispondeva.
- Sintomo:
  - [WorkspaceStore+ProjectContextSync.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift) usava `MainChatRustBridge.reduce(...) ?? ChatPipelineReducer.apply(...)`
  - [ConversationFlowCoordinator+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift) manteneva `runStreamLegacy(...)`
  - il watchdog produceva ancora messaggi/decisioni locali Swift prima del terminal state Rust
- Impatto: il runtime `main chat` non era ancora Rust-only sul path live del direct stream; in caso di bridge degradato il sistema tornava a semantica Swift locale.
- Gravita': alta
- Steps to reproduce:
  1. Forzare `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
  2. Eseguire `ConversationFlowCoordinator.runStream(...)`.
  3. Osservare che il vecchio path poteva ancora completare via fallback Swift invece di fallire chiuso.
- Risultato attuale: ownership del direct stream non era ancora 100% Rust.
- Risultato atteso: il loop Swift deve restare solo adapter `AsyncSequence`; riduzione evento, timeout semantics e finalizzazione devono essere owned da Rust e il path deve fallire chiuso se il runtime Rust non e' disponibile.
- Causa probabile: il cutover precedente aveva spostato il lifecycle e il timeout bookkeeping in Rust, ma non ancora il consumo del provider event e il fail-closed del direct stream.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_runtime.rs`
  - `Native/RustCore/src/main_chat/runtime.rs`
  - `Native/RustCore/src/main_chat/stream_runtime.rs`
  - `App/SoloCodeApp/Sources/Runtime/ConversationFlowCoordinator+Support.swift`
  - `App/SoloCodeApp/Sources/Runtime/WorkspaceStore+ProjectContextSync.swift`
  - `Tests/SoloCodeAppTests/ConversationFlowCoordinatorTests.swift`
  - `Config/validation/rust-cutover-swift-allowlist.txt`
  - `docs/bugs`
  - `docs/changelog`
  - `docs/migration`
- Non-scope:
  - rimozione totale del loop di attesa `AsyncSequence` da Swift
  - migrazione dei provider non-main-chat
  - ulteriori riclassificazioni nel dominio `Runtime` oltre al support bridge appena giustificato
- Moduli confinanti da verificare:
  - `ConversationFlowCoordinatorTests`
  - `ChatStreamFailureHandlingTests`
  - `rust_cutover_guard`
  - `WorkspaceStore+ProjectContextSync.swift`
- Test da aggiungere o aggiornare:
  - test Rust su `apply_direct_stream_provider_event`
  - test app-side che verifica fail-closed quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
- Strategia di fix minimo:
  - introdurre un'action runtime Rust per consumare provider event e aggiornare `turn_state` + `runtime_snapshot`
  - rimuovere il fallback `?? ChatPipelineReducer.apply(...)`
  - eliminare il fallback `runStreamLegacy(...)`
  - riclassificare come `binding_adapter` solo i file `Runtime` che dopo il fix restano bridge puri verso Rust
  - caricare esplicitamente la dylib review core nei test del coordinatore
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/ChatStreamFailureHandlingTests`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files \"<diff runtime>\" --format text`
- Commit previsto: `refactor(main-chat): make direct-stream runtime fail closed on rust`

## Effetto osservato
- il direct stream consuma ora gli eventi provider tramite action Rust dedicata
- il fallback reducer locale Swift e il path `runStreamLegacy(...)` sono stati rimossi
- il runtime fallisce chiuso quando il core Rust e' forzato off
- i file `ConversationFlowCoordinator+Support.swift` e `WorkspaceStore+ProjectContextSync.swift` vengono trattati come adapter Rust-backed, non come ownership business Swift residua
