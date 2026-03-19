# 2026-03-19 - Review panel chat findings snapshot via Rust

## Modifiche
- [CodeReviewPanelStore+ChatFindings.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift) invia ora lo snapshot corrente a `review_core_panel_chat_extract` e preferisce lo snapshot canonico restituito dal core Rust.
- [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/review_panel.rs) costruisce uno snapshot opzionale aggiornato con findings, eventi `finding_added`, mutation sequence, `lastUpdatedAt` e outcome.
- [review_panel.rs](/Users/benjaminstoica/SoloCode/Native/RustCore/src/ffi/review_panel.rs) allinea il boundary FFI al nuovo payload `snapshot`.

## Verifica eseguita
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests/testStructuredChatFindingsSyncsIntoFindingsTimelineAndDeduplicates`
- `cargo build --manifest-path /Users/benjaminstoica/SoloCode/Native/RustCore/Cargo.toml`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files App/SoloCodeApp/Sources/Panels/CodeReview/Views/Runtime/CodeReviewPanelStore+ChatFindings.swift --format text`

## Esito
- il panel review non dipende piu' solo da una ricostruzione Swift del merge findings chat-side
- il boundary strict review resta senza nuove violazioni
- il fallback locale resta disponibile solo come compatibilita' se il payload snapshot non e' presente
