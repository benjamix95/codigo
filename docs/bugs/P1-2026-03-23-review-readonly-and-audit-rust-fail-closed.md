## Bug Fix Record
- Categoria: A - Critico
- Bug: il boundary review Rust-first conservava ancora due ownership Swift residue: 1) `review_status` e `review_findings` potevano ricadere su query/rendering locali nel review harness, 2) `CodeReviewAuditService` continuava a eseguire audit security/bug in Swift anche quando il supporto Rust era il contratto corretto.
- Sintomo:
  - con `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`, `review_status` e `review_findings` restituivano ancora output locale invece di fallire chiusi;
  - diversi tool `audit_security_*` e `audit_bug_*` non fallivano chiusi quando il review core Rust non era disponibile.
- Impatto: ownership di dominio duplicata tra Swift e Rust nel boundary review, con rischio di drift su payload, filtri, summary e semantica degli audit.
- Gravita': P1
- Steps to reproduce:
  1. Forzare `SOLOCODE_REVIEW_CORE_FORCE_SWIFT=1`.
  2. Invocare `review_status` o `review_findings`.
  3. Osservare il fallback locale del review harness.
  4. Invocare `CodeReviewAuditService.runTool(...)` su tool come `audit_security_supply_chain` o `audit_bug_diff_risks`.
- Risultato attuale:
  - `review_status` e `review_findings` usavano ancora `MCPSharedState` come fallback locale;
  - `CodeReviewAuditService` trattava solo un sottoinsieme dei tool audit come Rust-required.
- Risultato atteso:
  - `review_status` e `review_findings` devono essere Rust-only o fallire esplicitamente;
  - l'intera famiglia audit security/bug deve essere Rust-required o restituire `unavailable/unsupported` esplicito, senza audit locale sostitutivo sul path standard.
- Causa probabile:
  - fallback di compatibilita' lasciati nel review harness;
  - classificazione incompleta dei tool audit Rust-backed nel servizio audit.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/ReviewCore/Audit/CodeReviewAuditService.swift`
  - `Tests/CoderEngineTests/Support/ReviewMCPHarness/CoderIDEMCPServerApp+ReviewHarnessReads.swift`
  - test review/audit associati
- Non-scope:
  - merge dei binari MCP Rust
  - riscrittura della UI review panel
  - rimozione completa di tutti i meta-tool host-side
- Moduli confinanti da verificare:
  - `CodeReviewAuditAdvancedTests`
  - `CodeReviewHandlerTests`
  - `SecurityHandlerTests`
  - `BugHunterHandlerTests`
- Test da aggiungere o aggiornare:
  - `review_status` e `review_findings` fail-closed quando Rust e' forzato off;
  - `audit_security_supply_chain` e `audit_bug_diff_risks` fail-closed quando Rust non e' disponibile.
- Strategia di fix minimo:
  - rendere `review_status` e `review_findings` dipendenti dal bridge Rust;
  - promuovere tutta la famiglia `ReviewAuditToolName.securityTools` e `ReviewAuditToolName.bugTools` a `requiredRustAuditToolResult`.
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerFailClosedTests -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`
- Commit previsto:
  - `refactor(review): fail closed readonly and audit paths without rust`
