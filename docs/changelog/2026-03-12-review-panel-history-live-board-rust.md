# 2026-03-12 - Review panel history live board snapshot-state in Rust

## Modifiche
- esteso `review_history.rs` con `derive_history_live_state(...)` per derivare worker/file board dallo snapshot `fileLedger`.
- esteso `review_core_reduce_panel_state` con l'operazione `derive_history_live_state`.
- aggiunto l'adapter Swift `CodeReviewPanelStore+RustHistoryLiveState.swift` per convertire il payload Rust nei model del panel.
- aggiornato `CodeReviewPanelStore+HistoryLive.swift` per preferire il reducer Rust quando lo snapshot contiene `fileLedger`.
- lasciato invariato il fallback basato su `TaskActivityStore`, che resta necessario quando il board dipende dalle activity live locali.
- aggiornato `Solo Code.xcodeproj/project.pbxproj` per includere il nuovo file Swift nel target app.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`

## Note
- la suite Rust e' verde, incluso il nuovo test `derives_history_live_state_from_file_ledger`.
- il build Apple-side arriva fino alla fase di lancio test, ma l'ambiente locale fallisce con assertion/crash `IDELaunchServicesLauncher` durante l'esecuzione della bundle; non e' un errore di compilazione del delta introdotto.

## Esito
- il live board storico basato su snapshot e' ora derivato dal core Rust
- Swift conserva solo il fallback che dipende dalle activity runtime locali dell'IDE
