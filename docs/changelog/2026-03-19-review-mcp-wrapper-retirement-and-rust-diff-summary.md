# 2026-03-19 - Review MCP wrapper retirement and Rust diff summary

## Modifiche
- rimossi dai target di produzione i wrapper Swift legacy review/security/bughunter sotto:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter`
- semplificato il dispatcher legacy `CoderIDEMCPServerApp+IDEStateTools.swift` eliminando il routing review/security/bughunter dal framework Swift ritirato
- aggiunto un harness test-side dedicato in `Tests/CoderEngineTests/Support/ReviewMCPHarness/` per preservare la copertura storica senza ricompilare quei wrapper nel prodotto
- sostituito il placeholder di `coderide_review_diff_summary` nel server Rust con il renderer diff summary reale basato su `review_diff::render_summary`
- esteso `Native/CoderideMCPServerRust/tests/server_smoke.rs` per coprire `coderide_review_diff_summary`

## Effetto
- il runtime MCP reale resta solo Rust
- la compatibilità storica dei test non passa più per file legacy buildati nei target applicativi
- il boundary strict review-scope non conta più i `9` wrapper MCP Swift rimasti

## Verifica prevista
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerTests+Validation -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests+Gate -only-testing:CoderEngineTests/BugHunterHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests+Start -only-testing:CoderEngineTests/CoderIDEMCPServerPlanToolsTests`
- audit strict review-scope
