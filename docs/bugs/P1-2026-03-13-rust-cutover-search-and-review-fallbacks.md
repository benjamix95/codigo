# P1 - Search semantica e review verification ricadevano ancora su ownership Swift

## Bug Fix Record
- Categoria: A - Critico
- Bug: la search semantica e la verifica dei review candidate mantenevano fallback locali Swift, e il launcher MCP consentiva ancora di riattivare il server Swift via env.
- Sintomo: il sistema poteva continuare a funzionare con semantica non canonica quando il core Rust non era disponibile, mascherando un cutover incompleto.
- Impatto: drift semantico tra runtime Rust e path Swift, regressioni difficili da riprodurre e impossibilita' di garantire che il non-UI fosse davvero Rust-owned.
- Gravita': alta
- Steps to reproduce:
  1. Avviare semantic search senza libreria Rust caricabile oppure con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
  2. Osservare che `RustSearchEngineBackend` restituiva comunque risultati tramite fallback Swift.
  3. Verificare un review candidate con core Rust disabilitato e osservare che `ReviewCandidateVerificationService` eseguiva ancora euristiche locali Swift.
  4. Avviare `CoderIDEMCPServerExecutable` con `SOLOCODE_USE_SWIFT_MCP_SERVER=1` e notare che il launcher poteva ancora reindirizzare al server Swift.
- Risultato attuale: search e candidate verification devono usare solo il core Rust; se Rust non e' disponibile devono fallire in modo esplicito, senza business logic locale Swift.
- Risultato atteso: backend search Rust di default, nessun fallback automatico a Swift, verifica candidate solo via Rust, launcher MCP senza override che riattivi il server Swift.
- Causa probabile: cutover Rust incompleto e mantenimento di reti di sicurezza Swift usate inizialmente per rollout graduale.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SearchEngineBackend.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/RustSearchEngineBackend.swift`
  - `Engine/CoderEngine/Sources/CodeReview/Verification/ReviewCandidateVerificationService.swift`
  - `Tools/CoderIDEMCPServerExecutable/Sources/CoderIDEMCPServerExecutableMain.swift`
  - test dedicati `Tests/CoderEngineTests/SemanticSearch/SearchEngineBackendTests.swift`
  - test dedicati `Tests/CoderEngineTests/CodeReview/ReviewCandidateVerificationServiceTests.swift`
- Non-scope:
  - migrazione completa di `CodeReviewAuditService`
  - migrazione completa di `ReviewPipelineCoordinator`
  - refactor UI/store del review panel
- Moduli confinanti da verificare:
  - `SemanticIndex`
  - `ReviewCoreBridge`
  - suite `CoderEngineTests`
- Test da aggiungere o aggiornare:
  - default backend search = Rust
  - nessun fallback risultati search quando Rust e' disabilitato
  - verification service ritorna errore esplicito quando Rust e' disabilitato
- Strategia di fix minimo:
  - invertire il default search a Rust
  - eliminare il fallback automatico del backend search
  - rimuovere il reducer/heuristic path locale da `ReviewCandidateVerificationService`
  - rimuovere l'override env del launcher MCP verso il server Swift
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_verify -- --nocapture`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SearchEngineBackendTests -only-testing:CoderEngineTests/ReviewCandidateVerificationServiceTests`
- Commit previsto: `refactor(rust-cutover): remove swift fallbacks from search and review verification`

## Note
- Restano fuori da questo slice altri ownership gap non-UI gia' noti: audit review, orchestration pipeline review e porzioni del runtime MCP Swift.
