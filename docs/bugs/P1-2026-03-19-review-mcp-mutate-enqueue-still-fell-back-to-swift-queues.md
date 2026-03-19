# P1 — review MCP mutate/enqueue conservava ancora fallback queue Swift

## Bug Fix Record
- Categoria: A
- Bug: i wrapper MCP Swift per `review_*`, `security_*` e `bughunter_*` continuavano a fare enqueue locale o start queue locale anche quando il runtime queue Rust non era disponibile.
- Sintomo: gli handler sotto `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers` validavano con il bridge Rust, ma poi chiamavano ancora:
  - `MCPSharedState.enqueueCodeReviewCommand(...)`
  - `MCPSharedState.enqueueBugHunterCommand(...)`
  - `VerifiedFindingsStartCommandService.enqueueReviewStart(...)`
- Impatto: ownership ancora sdoppiata sul surface MCP mutating/enqueue; il server Rust e il wrapper Swift potevano divergere su deduplica, fail-closed e command queue semantics.
- Gravita': alta, perche' tocca il boundary MCP review/security/bughunter che dovrebbe essere rust-only fuori dalla UI.
- Steps to reproduce:
  1. Forzare `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
  2. Invocare `review_revalidate_finding`, `security_start` o `bughunter_start` via handler Swift.
  3. Prima del fix, osservare che il wrapper poteva ancora accodare localmente invece di fallire closed.
- Risultato attuale: i wrapper MCP potevano ancora ricadere sulle queue Swift locali.
- Risultato atteso: i wrapper MCP devono usare solo entrypoint queue Rust-only e fallire esplicitamente se il runtime queue Rust non risponde.
- Causa probabile: la migrazione precedente aveva portato in Rust la preflight semantics e il server MCP Rust, ma il wrapper Swift manteneva ancora compat layer locale sulle queue.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewCommands.swift`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunterCommands.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/*`
  - `Tests/CoderEngineTests/{CodeReview,Security,BugHunter}/*`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - read-only MCP review/security/bughunter
  - hard cutover finale dei residui engine/verified findings
  - UI panel
- Moduli confinanti da verificare:
  - `CodeReviewHandlerTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`
  - `MCPSharedBugHunterCommandsTests`
- Test da aggiungere o aggiornare:
  - regressioni fail-closed sui wrapper MCP quando `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`
  - validazione queue shared-state
- Strategia di fix minimo:
  - esporre entrypoint `RustOnly` nel queue layer shared-state
  - far usare ai wrapper MCP solo queue Rust-only
  - rimuovere i path enqueue locali dai wrapper
  - mantenere la compatibilita' locale solo nel layer shared-state generico non MCP
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerFailClosedTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/SecurityHandlerFailClosedTests -only-testing:CoderEngineTests/BugHunterHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerFailClosedTests -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests`
- Commit previsto: `refactor(review-mcp): route wrapper enqueue through rust queue`
