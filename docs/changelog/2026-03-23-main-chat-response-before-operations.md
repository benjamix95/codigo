# 2026-03-23 — Main chat response before operations

## Modifiche
- il transport Codex app-server non bufferizza piu' il testo assistant fino al primo tool operativo
- la timeline chat rende i blocchi `reasoning` subito dopo il `primaryText`
- feed operativo e detail blocks restano dopo la risposta e il reasoning

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml codex_agent_message_gate -- --nocapture`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTurnTimelineOrderingTests`
