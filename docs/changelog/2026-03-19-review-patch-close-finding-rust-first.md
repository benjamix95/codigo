# 2026-03-19 — Review patch `close_finding` Rust-first

## Modifiche
- tolta la mutazione Swift locale per `close_finding` nel patch executor review
- instradata la chiusura del finding a un mutator Rust dello snapshot
- aggiunto gating Rust ai test di successo del patch close lifecycle

## Motivazione
- aprire la tranche 4 spostando un terminal step del patch lifecycle fuori dalla semantica Swift locale

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopCloseFindingTests`
