# 2026-03-12 - Review panel fallback snapshot mutations via Rust

## Modifiche
- `CodeReviewPanelStore+SnapshotMutation.swift` ora usa direttamente `review_core_command_mutate_snapshot` tramite request/response dedicate panel-side.
- il panel fallback non muta piu' localmente `findings` ed `events` con closure Swift.
- `CodeReviewPanelStore+Launch.swift` usa il mutator Rust per `dismiss`.
- `CodeReviewPanelStore+TargetedFix.swift` usa il mutator Rust per marcare `apply_fix` sullo snapshot sorgente.
- aggiunta regressione su `CodeReviewPanelSessionScopingTests` per verificare il fallback `wont_fix`.

## Validazione eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests`

## Note
- il build Swift passa il punto di compilazione del panel mutation path.
- il run della suite resta soggetto ai problemi ambientali del launch test su macOS gia' osservati in questa sessione.

## Esito
- panel fallback e command loop condividono ora lo stesso reducer Rust per le mutazioni snapshot principali
- il boundary review lato app riduce un altro path semantico duplicato in Swift
