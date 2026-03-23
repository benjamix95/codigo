# P1 — Queue MCP e shared-state review/bughunter erano ancora governati da Swift

## Bug Fix Record
- Categoria: A
- Bug: le queue `review` e `bughunter`, l’indice sessioni review e gran parte della shell tool MCP vivevano ancora in Swift, con logica distribuita tra `MCPSharedState`, handler MCP e command loop.
- Sintomo: validazioni, ordering, claim stale, heartbeat e formattazione read-only dei tool erano duplicati e difficili da mantenere coerenti col core Rust.
- Impatto: alto rischio di drift tra pipeline review Rust e layer MCP/shared-state, con regressioni più probabili su session resolution, enqueue/claim e output tool.
- Gravita': alta, perché tocca orchestration cross-process e command queue condivise.
- Steps to reproduce:
  1. Avviare o interrogare una review via tool MCP (`review_*`, `security_*`, `bughunter_*`).
  2. Seguire il flusso in `MCPSharedState`, `CodeReviewHandler`, `SecurityHandler`, `BugHunterHandler`.
  3. Osservare che la queue e la logica di risposta erano ancora decise da Swift.
- Risultato attuale: queue review/bughunter, indice review e shell read-only dei tool MCP devono delegare al core Rust, lasciando a Swift solo persistence/lock/adapter.
- Risultato atteso: il layer MCP usa Rust per business rules, ordering, validation e payload rendering, con Swift ridotto a bridge.
- Causa probabile: le tranche precedenti avevano migrato soprattutto compute e orchestrazione review, ma non il boundary cross-process MCP.
- Scope consentito:
  - `Native/RustCore/src/review_mcp/*`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/*`
- Non-scope:
  - UI panel SwiftUI
  - `ReviewPatchWorkflowService` come esecutore concreto
  - provider/runtime OS e git/process ownership
- Moduli confinanti da verificare:
  - `MCPSharedCodeReviewCommandsTests`
  - `MCPSharedBugHunterCommandsTests`
  - `CodeReviewHandlerTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`
  - `SoloCodeAppCodeReviewCommandLoopTests`
- Test da aggiungere o aggiornare:
  - unit test Rust su queue review/bughunter
  - regressioni handler MCP review/security/bughunter
  - smoke app-side sul command loop review
- Strategia di fix minimo:
  - introdurre un dominio Rust `review_mcp`
  - usare adapter Swift per persistence e locks, non per business rules
  - instradare gli handler MCP read-only e lo shared-state queue attraverso Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test ... -only-testing:CoderEngineTests/MCPSharedCodeReviewCommandsTests`
  - `xcodebuild test ... -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests`
  - `xcodebuild test ... -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
  - `xcodebuild test ... -only-testing:SoloCodeAppTests/SoloCodeAppCodeReviewCommandLoopTests`
- Commit previsto: `perf(review): move mcp review shared-state logic into rust core`
