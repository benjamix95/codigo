# 2026-03-12 - Review panel snapshot history fallback in Rust

## Modifiche
- convertito `Native/RustCore/src/review_history.rs` in un modulo ad albero:
  - `review_history/mod.rs`
  - `review_history/snapshot.rs`
- introdotto il reducer Rust `derive_historical_findings_from_snapshot(...)` per trasformare `CodeReviewSessionSnapshot` in `HistoricalFindingRecord` serializzabili.
- spostati in `ffi/review_history.rs` gli entrypoint history-specifici (`review_core_shape_historical_findings`, `review_core_find_duplicate`) per mantenere i file FFI sotto soglia.
- esteso `review_core_reduce_panel_state` con l'operazione `derive_history_records_from_snapshot`.
- aggiunto il nuovo adapter Swift `CodeReviewPanelStore+RustHistoricalFindings.swift`.
- `CodeReviewPanelStore+History.swift` ora delega a Rust:
  - derivazione record storici da snapshot
  - shape finale dei record
  - merge history gia' esistente
- lasciato il legacy fallback Swift come ultima rete di sicurezza se il bridge Rust non e' disponibile.
- riportato `CodeReviewPanelStore+History.swift` sotto il limite file del repo.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryLiveBoardTests`

## Note
- la suite Rust e' verde.
- il build Swift e dei test app-side passa, ma l'esecuzione della suite continua a fallire in questo ambiente per un problema LaunchServices/Xcode (`Failed to send resume to target process`), non per errori di compilazione del delta introdotto.

## Esito
- la history fallback derivata dagli snapshot review non e' piu' principalmente business logic Swift
- la zona panel/history si avvicina al modello finale in cui Swift resta adapter/presentazione sopra reducers Rust
