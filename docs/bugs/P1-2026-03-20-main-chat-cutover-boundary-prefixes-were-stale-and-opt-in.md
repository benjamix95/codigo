# P1 - Il boundary `main chat` del Rust cutover era parziale, stantio e ancora opt-in

## Bug Fix Record
- Categoria: A
- Bug: il gate `main chat` in [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh) usava prefissi parziali/non piu' canonici e richiedeva `SOLOCODE_MAIN_CHAT_CUTOVER=1`, quindi il freeze del dominio non era applicato in modo affidabile.
- Sintomo:
  - i prefissi puntavano a path storici o troppo stretti, ad esempio file singoli in `Accounts` e path `PipelineIntegrationService*` non allineati alla posizione reale sotto `Chat/Support/PipelineRuntime`
  - un diff dentro il dominio reale `main chat` poteva passare senza enforcement se non esportava la variabile `SOLOCODE_MAIN_CHAT_CUTOVER=1`
  - il guard produceva un falso senso di copertura strutturale del dominio
- Impatto: le tranche successive del cutover `main chat -> Rust` potevano avanzare senza ridurre davvero il backlog Swift non-UI del dominio, rendendo il gate poco difendibile contro regressioni strutturali.
- Gravita': alta, perche' il problema tocca il meccanismo che deve impedire nuova deriva architetturale nel dominio principale della chat.
- Steps to reproduce:
  1. Toccare un file reale sotto `App/SoloCodeApp/Sources/Chat/**` o `App/SoloCodeApp/Sources/Accounts/**` non coperto dai vecchi prefissi.
  2. Eseguire `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "<diff>" --format text`.
  3. Osservare che, senza `SOLOCODE_MAIN_CHAT_CUTOVER=1`, il dominio `main chat` non veniva promosso a tranche gate hard-fail/budgeted.
- Risultato attuale: il boundary `main chat` non copriva in modo robusto il dominio reale e lasciava enforcement opzionale.
- Risultato atteso: il diff che entra nei prefissi canonici `main chat` deve attivare sempre il tranche gate, usando directory reali del dominio e non path storici/singoli file.
- Causa probabile: il gate `main chat` e' nato in tranche iniziali come protezione opt-in e non e' stato riallineato quando i file Swift sono stati spostati/spezzati in nuove cartelle di supporto.
- Scope consentito:
  - [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh)
  - `Native/AppCoreRust/tests/*boundary*`
  - `docs/migration`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - migrazione runtime/store/provider aggiuntiva verso Rust
  - aggiornamenti funzionali UI/main chat
  - attivazione del gate finale `zero legacy` su tutto il dominio
- Moduli confinanti da verificare:
  - `rust_cutover_guard`
  - allowlist `Config/validation/rust-cutover-swift-allowlist.txt`
  - `scripts/solocode-validate`
- Test da aggiungere o aggiornare:
  - regressione Rust sul caso `candidate list parziale + prefisso largo App/SoloCodeApp/Sources/Chat`
  - regressione Rust sul caso `candidate list parziale + prefisso largo App/SoloCodeApp/Sources/Accounts`
- Strategia di fix minimo:
  - sostituire i prefissi `main chat` con i prefissi canonici di directory
  - attivare l'enforcement automaticamente quando il diff entra nel dominio
  - documentare baseline e backlog ordinato per priorita'
- Verifica post-fix:
  - `cargo test --manifest-path /Users/benjaminstoica/SoloCode/Native/AppCoreRust/Cargo.toml`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files scripts/validate_rust_cutover_boundary.sh,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs --format text`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files scripts/validate_rust_cutover_boundary.sh,Native/AppCoreRust/tests/app_core_boundary_main_chat.rs,docs/bugs/P1-2026-03-20-main-chat-cutover-boundary-prefixes-were-stale-and-opt-in.md,docs/changelog/2026-03-20-main-chat-cutover-tranche0-freeze-and-guardrail.md,docs/migration/RUST_CUTOVER_MAIN_CHAT_BASELINE_2026-03-20.md`
- Commit previsto: `fix(validation): enforce canonical main-chat rust cutover prefixes`

## Effetto osservato
- il dominio `main chat` entra ora sempre nel tranche gate quando il diff tocca i prefissi canonici
- il baseline del dominio torna auditabile con lo stesso perimetro usato dalla validation
- la riduzione del backlog Swift non-UI torna un'invariante verificabile invece di dipendere da un flag manuale
