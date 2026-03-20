# Changelog - 2026-03-20 - Main Chat Tail Finalization Rust Tranche

## Obiettivo
- Completare il drenaggio del path standard `direct-stream` spostando la finalizzazione del turno fuori da Swift e chiudendo un’altra unità strutturale nel prefisso `Chat`.

## Modifiche principali
- `handleStreamResult(...)` in `ChatPanelView+PartR_Tail.swift` non finalizza più il turno standard con helper legacy:
  - niente `applyLegacyStreamSnapshot(...)` nel success path standard
  - niente `applyLegacyLifecycleEvent(.turnCompleted, ...)` nel success path standard
  - il commit terminale passa da `main_chat_ui`
- Il catch del ramo standard in `ChatPanelView+PartL_SendMessageExecution.swift` usa il boundary Rust anche per:
  - `stream_finish_failure`
  - `stream_interrupt`
- `main_chat_ui` ora applica anche l’override del testo terminale nello store snapshot sincronizzato.
- I test del boundary UI sono stati separati in `RustMainChatUIBoundaryTests.swift`, mantenendo il file originario sotto il limite operativo.

## Riduzione strutturale
- Rimosso `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartQ_StreamCommit.swift`
- Rimosso `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+.swift`
- Estratto `ChatPanelView+PartQ_Walkthrough.swift` per mantenere i file sotto controllo dimensionale

## Test eseguiti
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building ... -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit ...`

## Esito tranche
- `Legacy hard-fail attivi` nel prefisso `Chat`: `85`
- `Legacy oltre budget nel tranche gate`: `0`
- Il path standard `direct-stream` non dipende più dalla finalizzazione legacy Swift per success/failure terminali.
