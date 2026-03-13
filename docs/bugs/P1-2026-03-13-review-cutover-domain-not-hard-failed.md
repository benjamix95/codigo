# P1 - Il cutover Rust del dominio review non era ancora hard-failed dalla validation

## Bug Fix Record
- Categoria: A
- Bug: il boundary guard bloccava solo nuovi file Swift non-UI, ma non poteva promuovere il dominio `Code Review` a tranche hard-fail.
- Sintomo: una modifica dentro `App/SoloCodeApp/Sources/Panels/CodeReview` o nei moduli review collegati continuava a passare la validation anche se nel dominio restavano numerosi file Swift non-UI legacy.
- Impatto: il piano "Code Review prima" non era realmente enforceable; il repo poteva continuare a muoversi nel dominio review senza chiudere il debito Swift non-UI residuo.
- Gravità: P1
- Steps to reproduce:
  1. Modificare un file sotto `App/SoloCodeApp/Sources/Panels/CodeReview/`.
  2. Eseguire `scripts/validate_rust_cutover_boundary.sh` con il vecchio guard.
  3. Osservare che il comando fallisce solo per nuovi file Swift non-UI, non per il backlog legacy del dominio review.
- Risultato attuale: il guard censiva il backlog review ma non poteva usarlo come criterio di hard-fail per una tranche dedicata.
- Risultato atteso: quando il diff tocca il dominio review, la validation deve scansionare tutto il perimetro review e fallire se esiste ancora Swift non-UI legacy fuori da UI/bootstrap consentiti.
- Causa probabile: la tranche iniziale del cutover era stata progettata come freeze del debito, non come gate di chiusura per domini specifici.
- Scope consentito:
  - `Native/AppCoreProtocol`
  - `Native/AppCoreRust`
  - `scripts/validate_rust_cutover_boundary.sh`
- Non-scope:
  - drenaggio reale dei file Swift review verso Rust
  - refactor del runtime review/panel
  - modifiche UI
- Moduli confinanti da verificare:
  - `scripts/solocode-validate`
  - DTO `BoundaryAudit*`
  - integrazione cargo del guard
- Test da aggiungere o aggiornare:
  - regressione Rust per `enforce_legacy_zero_prefixes`
  - verifica della raccolta completa del prefisso review anche con candidate list parziale
- Strategia di fix minimo:
  - estendere il protocollo del guard con prefissi hard-fail
  - far scansionare l'intero prefisso review quando il diff entra nel dominio
  - mantenere invariato il comportamento per gli altri domini legacy
- Verifica post-fix:
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files Native/AppCoreProtocol/src/app_core.rs,Native/AppCoreRust/src/boundary/audit.rs,Native/AppCoreRust/src/bin/rust_cutover_guard.rs,Native/AppCoreRust/tests/app_core_boundary.rs,scripts/validate_rust_cutover_boundary.sh,docs/bugs/P1-2026-03-13-review-cutover-domain-not-hard-failed.md,docs/changelog/2026-03-13-rust-cutover-review-domain-hard-fail.md,docs/migration/RUST_CUTOVER_BOUNDARY_BASELINE_2026-03-13.md`
- Commit previsto: `fix(cutover): hard-fail review rust boundary tranche`

## Fix applicato
- aggiunto al boundary audit Rust il concetto di `enforce_legacy_zero_prefixes`
- il guard puo' ora contare separatamente i file Swift non-UI legacy presenti nei prefissi hard-fail
- la validation shell attiva automaticamente il gate review quando il diff tocca i prefissi del dominio review

## Residuo
- il dominio review non e' ancora migrato a Rust: il nuovo gate rende il debito bloccante, ma non lo drena da solo
- il gate repo-wide resta volutamente disattivato finche' la tranche review non viene chiusa davvero
