# P1 - I tool MCP `start` di review/security/bughunter mantenevano ancora preflight Swift-owned

## Bug Fix Record
- Categoria: A
- Bug: i path `review_start`, `security_start` e parte di `bughunter_start` continuavano a replicare in Swift validazione e preflight gia' presenti nel core Rust.
- Sintomo: il routing MCP passava dal bridge Rust solo in parte, ma gli handler conservavano ancora fallback/validazioni locali per scope, gate e source kind.
- Impatto: rischio di drift tra host MCP Swift e dispatcher Rust su messaggi d’errore, validazione input e cutover del runtime review-first.
- Gravita': alta, perche' tocca il boundary dei tool MCP review.
- Steps to reproduce:
  1. Chiamare `review_start`, `security_start` o `bughunter_start`.
  2. Seguire gli handler MCP in `Tools/CoderIDEMCPServer`.
  3. Osservare il preflight Swift locale prima dell’enqueue.
- Risultato attuale: l’host Swift manteneva ancora semantica propria per il preflight `start`.
- Risultato atteso: il preflight dei tool `start` deve passare dal dispatcher Rust; Swift deve limitarsi all’enqueue del side effect finale e alla persistenza locale.
- Causa probabile: la migrazione MCP review aveva coperto read-only e queueable actions, ma non aveva ancora chiuso i path `start`.
- Scope consentito:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview/CodeReviewHandler+Start.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter/BugHunterHandler+Commands.swift`
  - `Tests/CoderEngineTests/BugHunter/BugHunterHandlerTests+Start.swift`
  - `Solo Code.xcodeproj/project.pbxproj`
  - `docs/bugs`, `docs/changelog`
- Non-scope:
  - route MCP read-only che dipendono ancora da servizi Swift non migrati
  - cutover completo dell’host MCP sul server Rust nativo
  - UI del review panel
- Moduli confinanti da verificare:
  - `CodeReviewHandlerTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`
- Test da aggiungere o aggiornare:
  - regressione `bughunter_start` invalid source kind via preflight Rust
  - riuso delle suite esistenti per `review_start` e `security_start`
- Strategia di fix minimo:
  - rendere obbligatorio il preflight Rust nei tre handler `start`
  - lasciare a Swift solo l’enqueue service/persistenza dopo validazione Rust riuscita
  - rimuovere i fallback di validazione locali non piu' necessari
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`
  - `xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
  - in questo ambiente il build/test host resta soggetto ai problemi LaunchServices / code signature dei bundle test
- Commit previsto: `refactor(review-mcp): require rust preflight for start tools`
