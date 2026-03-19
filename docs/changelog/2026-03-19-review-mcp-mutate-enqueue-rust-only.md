# 2026-03-19 — Review MCP mutate/enqueue rust-only

## Modifiche
- aggiunti entrypoint shared-state `RustOnly` per le queue review e bughunter:
  - `enqueueCodeReviewCommandRustOnly(...)`
  - `enqueueUniqueCodeReviewStartCommandRustOnly(...)`
  - `enqueueBugHunterCommandRustOnly(...)`
- i wrapper MCP Swift review/security/bughunter non fanno piu' enqueue locale:
  - niente piu' `enqueueCodeReviewCommand(...)`
  - niente piu' `enqueueBugHunterCommand(...)`
  - niente piu' `enqueueReviewStart(...)` nel path MCP
- i wrapper MCP falliscono closed se il runtime queue Rust non risponde
- aggiunte regressioni fail-closed dedicate nei test handler

## Motivazione
- completare la tranche MCP mutate/enqueue eliminando l'ownership queue Swift dal surface MCP review/security/bughunter

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerFailClosedTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/SecurityHandlerFailClosedTests -only-testing:CoderEngineTests/BugHunterHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerFailClosedTests -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests`

## Note
- nell'host `CoderEngineTests` il dylib Rust non risulta caricabile in questo ambiente; le suite nominali handler vengono quindi saltate esplicitamente dal setup, mentre le nuove regressioni fail-closed restano eseguite.
