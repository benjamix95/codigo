# P1 - Il reasoning stream reducer della main chat viveva ancora in Swift

## Bug Fix Record
- Categoria: A
- Bug: il reducer del reasoning stream (`presentation policy`, `selected conversation guard`, merge dei blocchi e dei segmenti reasoning) viveva ancora in Swift.
- Sintomo:
  - `ChatReasoningPresentationPolicy` in Swift
  - `shouldUpdateInlineReasoningState(...)` in Swift
  - `ChatReasoningStreamReducer.apply(...)` in Swift
- Impatto: una porzione del runtime live di streaming della `main chat` restava fuori dal cutover Rust, con ownership Swift di logica di dominio.
- Gravita': alta
- Steps to reproduce:
  1. Aprire [ChatReasoningStreamReducer.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/Support/Streaming/ChatReasoningStreamReducer.swift).
  2. Verificare che policy e reducer reasoning siano implementati interamente lato Swift.
- Risultato attuale: il reasoning stream path non era ancora Rust-owned.
- Risultato atteso: Swift espone solo un bridge sottile, mentre policy e reducer vivono in Rust.
- Causa probabile: il cutover del runtime live si era fermato su provider/session/store, lasciando il reducer UI-streaming come residuo locale.
- Scope consentito:
  - `Native/AppCoreProtocol/src/main_chat_reasoning.rs`
  - `Native/RustCore/src/main_chat/reasoning_stream.rs`
  - `Native/RustCore/src/ffi/main_chat.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/MainChatProviderBridgeModels.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatCLIAccountSnapshots.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Streaming/ChatReasoningStreamReducer.swift`
  - `Tests/SoloCodeAppTests/ChatReasoningStreamReducerTests.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - `upsertSeparateThinkingMessage(...)`
  - finalizzazione dei reasoning blocks nel transcript
  - policy review/debug fuori dal reasoning stream
- Moduli confinanti da verificare:
  - `ChatPanelView+PartO_Streaming1.swift`
  - `ChatPanelView+PartP_Streaming2.swift`
  - `ChatReasoningStreamReducerTests`
- Test da aggiungere o aggiornare:
  - test Rust del reducer/presentation mode
  - XCTest di parity sul bridge `ChatReasoningStreamReducerTests`
- Strategia di fix minimo:
  - introdurre contratto shared `main_chat_reasoning`
  - implementare il reducer Rust dedicato
  - assorbire il bridge pubblico in un file Swift gia' allowlisted sotto `Providers/Rust/**`
  - eliminare il file Swift legacy del reducer
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml reasoning_stream -- --nocapture`
  - `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -parallel-testing-enabled NO -derivedDataPath /tmp/solocode-reasoning-dd -only-testing:SoloCodeAppTests/ChatReasoningStreamReducerTests`
- Commit previsto:
  - `refactor(chat): move reasoning stream reducer into rust`
