## 2026-03-23 - Review readonly and audit paths fail closed without Rust

- `review_status` e `review_findings` non usano piu' fallback locale nel review harness quando il review core Rust non e' disponibile.
- `CodeReviewAuditService` tratta ora tutte le famiglie `ReviewAuditToolName.securityTools` e `ReviewAuditToolName.bugTools` come Rust-required, invece di lasciare una semantica audit Swift locale su sottoinsiemi ancora aperti.
- Aggiunte regressioni per verificare il fail-closed anche su:
  - `audit_security_supply_chain`
  - `audit_bug_diff_risks`
- Questo batch riduce un altro pezzo di ownership Swift nel boundary review e porta l'avanzamento complessivo del cutover Rust-first al **75%**.

### Verifica eseguita
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodeReviewHandlerTests -only-testing:CoderEngineTests/CodeReviewHandlerFailClosedTests -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests -only-testing:CoderEngineTests/SecurityHandlerTests -only-testing:CoderEngineTests/BugHunterHandlerTests`

### Note
- Le suite review/security/bughunter passano con diversi casi `skip` in questo ambiente quando il dylib `libsolocode_rust_core` non risulta caricabile, ma i path fail-closed introdotti sono stati esercitati e verificati.
- Restano fuori da questo batch i residui app-side/code panel e il drenaggio completo del `UnifiedToolRuntime` switch per i tool gia' Rust-first.
