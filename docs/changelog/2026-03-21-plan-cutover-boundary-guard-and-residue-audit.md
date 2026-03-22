# 2026-03-21 plan cutover boundary guard and residue audit

## Summary
- aggiunta copertura di boundary per il residuo `plan` non-UI ancora presente sotto `App/SoloCodeApp/Sources/Services`
- documentato il fatto che il cutover del `plan` non è ancora completamente chiuso dal punto di vista del gate legacy
- Mermaid non è stato toccato e resta fuori scope per questa tranche

## Changes
- `Native/AppCoreRust/tests/app_core_boundary_main_chat.rs`
  - nuovo caso di regressione che verifica i tre helper plan residui come legacy non-UI sotto il prefisso `Services`
- `docs/bugs/P2-2026-03-21-main-chat-plan-cutover-still-had-swift-residue-in-services.md`
  - nuovo bug record che fotografa il residuo e il contratto atteso del boundary

## Validation
- `cargo test -p app_core_rust --test app_core_boundary_main_chat`
- `cargo test -p app_core_rust`
- `cargo test -p solocode_rust_core`
