# P1 - I wrapper MCP review legacy erano ancora compilati nei target di produzione

## Bug Fix Record
- Categoria: A
- Bug: i wrapper Swift sotto `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/{ReviewBootstrap,Security,BugHunter}` erano già fuori dal runtime reale, ma continuavano a essere compilati nei target `CoderIDEMCPServer` e `CoderIDEMCPServerExecutable`.
- Sintomo: il binario MCP reale esegue direttamente `coderide-mcp-server-rust`, ma il framework legacy trascinava ancora routing e queue review/security/bughunter dentro la build Xcode.
- Impatto: il cutover tools rust-only restava incompleto e il boundary strict review-scope continuava a contare `9` file Swift non-UI pur non essendo più un path vivo del prodotto.
- Gravità: P1
- Steps to reproduce:
  1. Aprire `Tools/CoderIDEMCPServer/Sources/Runtime/CoderIDEMCPServerApp.swift`.
  2. Verificare che `main()` fallisce esplicitamente perché il runtime Swift è ritirato.
  3. Aprire `Solo Code.xcodeproj/project.pbxproj` e osservare che i file `ReviewBootstrap`, `Security` e `BugHunter` erano ancora nelle source phases dei target MCP Swift.
- Risultato attuale: il codice review-specifico legacy veniva ancora compilato nei target di produzione, pur essendo usato di fatto solo dai test.
- Risultato atteso: il target di produzione deve smettere di compilare quei wrapper; i test che coprono quella semantica devono usare un harness dedicato nel target test.
- Causa probabile: il runtime Rust è stato attivato prima del cleanup finale dei target Swift legacy e dei test storici.
- Scope consentito:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `Tests/CoderEngineTests/Support/ReviewMCPHarness/*`
  - `Native/CoderideMCPServerRust/src/review_tools.rs`
  - `Native/CoderideMCPServerRust/tests/server_smoke.rs`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - migrazione completa di `Engine/CoderEngine/Sources/CodeReview`
  - rimozione del catalogo metadata `CoderIDETools`
  - UI Swift del review panel
- Moduli confinanti da verificare:
  - `CoderEngineTests/CodeReview/*`
  - `CoderEngineTests/Security/*`
  - `CoderEngineTests/BugHunter/*`
  - `Native/CoderideMCPServerRust/tests/server_smoke.rs`
- Test da aggiungere o aggiornare:
  - harness test-side per `handleCodeReviewTool`, `handleSecurityTool`, `handleBugHunterTool`
  - integrazione Rust server per `coderide_review_diff_summary`
- Strategia di fix minimo:
  - rimuovere review/security/bughunter dal dispatcher Swift di produzione
  - eliminare i 9 file legacy dai target Xcode
  - spostare la compatibilità storica nel solo target test con un harness dedicato
  - chiudere il placeholder `coderide_review_diff_summary` nel server Rust reale
- Verifica post-fix:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerTests+Validation -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests+Gate -only-testing:CoderEngineTests/BugHunterHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests+Start -only-testing:CoderEngineTests/CoderIDEMCPServerPlanToolsTests`
  - audit strict review-scope
- Commit previsto: `refactor(review-mcp): retire compiled swift wrappers`
