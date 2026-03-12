# 2026-03-12 - Review panel chat findings merge via Rust

## Modifiche
- aggiunto `Native/RustCore/src/review_chat.rs` con il reducer `merge_chat_findings`.
- esteso `review_core_reduce_panel_state` con l'operazione `merge_chat_findings`.
- aggiunto l'adapter Swift `CodeReviewPanelStore+RustChatFindings.swift`.
- `CodeReviewPanelStore+ChatFindings.swift` ora prova il merge/dedup via Rust e usa il path Swift solo come fallback.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file Swift nel target app.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`

## Note
- la suite Rust e' verde, incluso il nuovo test su `merge_chat_findings`.
- la build app-side passa; l'esecuzione dei test continua a essere bloccata in ambiente al launch della app di test.

## Esito
- il path chat review -> findings tab non dipende piu' esclusivamente da dedup locale Swift
- un altro reducer panel-side e' stato spostato verso il core Rust
