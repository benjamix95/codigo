# 2026-03-20 — Message Tool Trace Core Consolidation

## Modifiche
- assorbiti gli helper di diff e compact preview in [MessageToolTraceView+Helpers.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Helpers.swift)
- rimosso il file legacy [MessageToolTraceView+Diff.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Diff.swift)
- aggiornato [Solo Code.xcodeproj/project.pbxproj](/Users/benjaminstoica/SoloCode/Solo%20Code.xcodeproj/project.pbxproj) per eliminare il riferimento al file rimosso

## Risultato
- il cluster `MessageToolTrace` perde un wrapper/helper legacy reale senza cambiare il comportamento osservabile
- la logica di formatting di diff, duration e compact preview resta confinata in un solo modulo di supporto sotto soglia dimensionale
- il prefisso `Chat` riduce ulteriormente la superficie legacy non-UI senza toccare runtime, planning o provider path

## Verifiche
- `cargo test --manifest-path Native/RustCore/Cargo.toml main_chat::ui`
- `cargo test --manifest-path Native/RustCore/Cargo.toml stream_runtime`
- `cargo build --manifest-path Native/RustCore/Cargo.toml`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test main_chat_ui`
- `cargo test --manifest-path Native/AppCoreRust/Cargo.toml --test app_core_boundary_main_chat`
- `xcodebuild build-for-testing -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`
- `xcodebuild test-without-building -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatProviderFactoryTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/ConversationFlowCoordinatorTests -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --files 'App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Helpers.swift,App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Diff.swift,App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+State.swift,App/SoloCodeApp/Sources/Chat/MessageToolTrace/MessageToolTraceView+Loaders.swift,Tests/SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests.swift'`
