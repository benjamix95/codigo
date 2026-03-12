# 2026-03-12 — Review history rust fallback tranche

## Scope
- fallback storico del review panel derivato dagli snapshot review
- eliminazione del legacy shaping Swift nel tab History

## Modifiche
- rimosso il motore legacy Swift che materializzava `HistoricalFindingRecord` da snapshot review
- lasciato al panel solo il path Rust `derive_history_records_from_snapshot` + `shape_historical_findings`
- ridotto il merge history locale a semplice consumo del risultato Rust
- aggiunto test Rust su snapshot history con patch applicata e validata
- aggiunta regressione app-side dedicata al fallback history da snapshot

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
- `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryTests -only-testing:SoloCodeAppTests/ReviewPanelFindingsHistoryRustFallbackTests`

## Note
- in questa macchina il build Swift passa, ma l'esecuzione dei bundle `xctest` resta bloccata da policy di code signature / launch del test host
