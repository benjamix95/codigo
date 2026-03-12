# P1 - I tool MCP read-only review/security/bughunter conservavano ancora fallback Swift duplicati

## Bug Fix Record
- Categoria: A
- Bug: i path read-only `review_status`, `review_findings`, `review_list_sessions`, `review_get_outcome`, `security_status`, `security_findings`, `bughunter_status`, `bughunter_findings`, `bughunter_run_history` e `bughunter_explain_cluster` potevano ancora ricadere su rendering/query Swift locali.
- Sintomo: anche con bridge Rust disponibile, l'host MCP manteneva una seconda semantica read-only nel codice handler.
- Impatto: rischio di drift tra dispatcher Rust e host Swift su payload testuali, filtri, summary e cutover del boundary MCP review-first.
- Gravita': alta, perche' tocca il surface read-only dei tool MCP review.
- Steps to reproduce:
  1. Invocare uno dei tool read-only review/security/bughunter.
  2. Seguire gli handler MCP in `Tools/CoderIDEMCPServer`.
  3. Osservare il fallback Swift dopo il branch `rust*ToolResult(...)`.
- Risultato attuale: il tool poteva ancora rispondere da logica Swift locale.
- Risultato atteso: quando il supporto Rust esiste gia', l'host MCP deve usare solo il bridge Rust e fallire esplicitamente se il core non e' disponibile.
- Causa probabile: la migrazione precedente aveva privilegiato i path mutating e di start, lasciando i read-only con fallback di compatibilita'.
- Scope consentito:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/*`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/*`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - route MCP che non hanno ancora supporto Rust
  - runtime execution review
  - UI del review panel
- Moduli confinanti da verificare:
  - `CodeReviewHandlerTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`
- Test da aggiungere o aggiornare:
  - riuso delle suite MCP esistenti per verificare che il rendering resti stabile
- Strategia di fix minimo:
  - rendere obbligatorio il bridge Rust nei tool read-only gia' supportati
  - rimuovere i fallback Swift duplicati
  - mantenere invariati i tool ancora non coperti dal core Rust
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
  - in questo ambiente il build arriva al lancio ma il bundle `CoderEngineTests.xctest` resta bloccato da code-signature/system policy
- Commit previsto: `refactor(review-mcp): remove swift readonly fallbacks`
