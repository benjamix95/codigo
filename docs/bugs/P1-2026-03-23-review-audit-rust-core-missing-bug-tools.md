# P1 — 2026-03-23 — Review audit bug tools esposti dal server MCP ma assenti nel core Rust

## Bug Fix Record
- Categoria: A — Critico
- Bug: il server MCP Rust esponeva `coderide_audit_bug_error_handling`, `coderide_audit_bug_state_machine` e `coderide_audit_bug_test_gaps`, ma `Native/RustCore/src/review_audit.rs` non implementava i corrispondenti `audit_bug_*`.
- Sintomo: nel pannello test gli entry risultavano rossi con messaggio `tool not implemented in rust core`.
- Impatto: audit bug-hunting incompleti e rumorosi; il pannello mostrava failure infrastrutturali invece di risultati reali.
- Gravita': alta
- Steps to reproduce:
  1. invocare uno dei tool MCP `coderide_audit_bug_error_handling`, `coderide_audit_bug_state_machine`, `coderide_audit_bug_test_gaps`
  2. osservare la risposta del server MCP Rust
- Risultato attuale: il server traduceva `unsupported_tool` in `tool not implemented in rust core`.
- Risultato atteso: i tool esposti dal catalogo MCP devono avere implementazione rust-backed coerente o non essere esposti.
- Causa probabile: drift tra `Native/CoderideMCPServerRust/src/tool_names.txt` / `audit_tools.rs` e il dispatcher `run_audit(...)` del core Rust.
- Scope consentito:
  - `Native/RustCore/src/review_audit.rs`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - refactor del service audit Swift
  - altri tool audit non coinvolti nello screenshot
- Moduli confinanti da verificare:
  - bridge FFI `review_core_run_audit`
  - `Native/CoderideMCPServerRust/src/audit_tools.rs`
- Test da aggiungere o aggiornare:
  - regressione che verifica supporto Rust per `audit_bug_state_machine`, `audit_bug_error_handling`, `audit_bug_test_gaps`
- Strategia di fix minimo:
  - aggiungere implementazioni Rust minime e coerenti per i tre tool mancanti
  - mantenere lo stesso formato payload/summary già usato dagli audit esistenti
- Verifica post-fix:
  - `cargo test --manifest-path Native/RustCore/Cargo.toml review_audit -- --nocapture`
- Commit previsto: `fix(review-audit): implement missing rust bug tools`
