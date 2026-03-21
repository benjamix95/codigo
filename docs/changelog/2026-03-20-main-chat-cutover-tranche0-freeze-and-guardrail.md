# 2026-03-20 — Main Chat Cutover Tranche 0: freeze e guardrail canonici

## Modifiche
- aggiornato [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh):
  - rimossi i prefissi `main chat` stantii e troppo stretti
  - adottati i prefissi canonici di dominio:
    - `App/SoloCodeApp/Sources/Chat`
    - `App/SoloCodeApp/Sources/Runtime`
    - `App/SoloCodeApp/Sources/Accounts`
    - `App/SoloCodeApp/Sources/Settings/ProviderFactory/Providers`
    - `Engine/CoderEngine/Sources/Pipeline`
    - `Engine/CoderEngine/Sources/Providers`
  - enforcement `main chat` reso automatico quando il diff entra nel dominio, senza piu' dipendere da `SOLOCODE_MAIN_CHAT_CUTOVER=1`
  - rinominato il file temporaneo baseline in forma generica `rust-cutover-baseline-json.*`
- aggiunte regression Rust in [app_core_boundary_main_chat.rs](/Users/benjaminstoica/SoloCode/Native/AppCoreRust/tests/app_core_boundary_main_chat.rs) per coprire:
  - prefisso largo `App/SoloCodeApp/Sources/Chat` con `candidate_files` parziale e backlog nested
  - prefisso largo `App/SoloCodeApp/Sources/Accounts` con `candidate_files` parziale e backlog nested
- aggiunto il bug record [P1-2026-03-20-main-chat-cutover-boundary-prefixes-were-stale-and-opt-in.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-20-main-chat-cutover-boundary-prefixes-were-stale-and-opt-in.md)
- documentata la baseline del dominio in [RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md)

## Risultato
- il freeze `main chat` ora usa lo stesso perimetro canonico del piano di migrazione
- il tranche gate non puo' piu' essere bypassato per semplice assenza di env var o path legacy non piu' allineati
- il backlog del dominio torna misurabile in modo stabile:
  - `198` legacy Swift non-UI nel baseline del 2026-03-20
  - `Chat 118`, `Accounts 34`, `Providers 33`, `Runtime 13`

## Verifica
- `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "scripts/validate_rust_cutover_boundary.sh,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs" --format text`
- `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "scripts/validate_rust_cutover_boundary.sh,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs,docs/bugs/P1-2026-03-20-main-chat-cutover-boundary-prefixes-were-stale-and-opt-in.md,docs/changelog/2026-03-20-main-chat-cutover-tranche0-freeze-and-guardrail.md,docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md"`

## Note
- questa tranche non sposta altro runtime business in Rust
- chiude pero' il prerequisito strutturale: da ora ogni modifica nel dominio `main chat` deve ridurre backlog reale o restare fuori dal perimetro
- follow-up hotfix 2026-03-21:
  - [main-chat-markers-bridge-bootstrap-guard.md](/Users/benjaminstoica/SoloCode/docs/changelog/2026-03-21-main-chat-markers-bridge-bootstrap-guard.md)
  - [main-chat-markers-runtime-fallback.md](/Users/benjaminstoica/SoloCode/docs/changelog/2026-03-21-main-chat-markers-runtime-fallback.md)
  - [rust-codex-path-resolution-parity.md](/Users/benjaminstoica/SoloCode/docs/changelog/2026-03-21-rust-codex-path-resolution-parity.md)
  - nessun cambiamento di scope o ownership della baseline: solo hardening e parity sui boundary gia' aperti nella tranche 0
