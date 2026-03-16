# P1 - Il repository non e' ancora 100% Rust fuori dalla UI e il dominio CodeReview conserva 72 file Swift non-UI

## Bug Fix Record
- Categoria: A - Critico
- Bug: il progetto non puo' ancora essere considerato migrato a Rust fuori dalla UI; il dominio `CodeReview` mantiene ancora file Swift non-UI attivi nel panel, nel bootstrap app, nell'engine review, in `VerifiedFindingsCore` e nel tooling MCP.
- Sintomo: un audit completo del workspace segnala ancora `1497` file Swift legacy non-UI; restringendo il perimetro ai prefissi review il conteggio resta `72`.
- Impatto: il boundary architetturale "UI Swift, runtime Rust" non e' ancora vero; finche' resta questo debito il panel review e il runtime associato possono continuare ad evolvere fuori dal perimetro Rust previsto.
- Gravita': alta
- Steps to reproduce:
  1. Eseguire `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist Config/validation/rust-cutover-swift-allowlist.txt --fail-on-legacy-non-ui --format text`.
  2. Osservare che il comando termina con exit code `2`.
  3. Eseguire l'audit review-scope descritto nel report `docs/migration/RUST_CUTOVER_AUDIT_2026-03-16.md`.
  4. Osservare che i prefissi review accumulano ancora `72` file Swift non-UI.
- Risultato attuale: esiste ora una modalita' strict del guard Rust che rende il problema verificabile in modo binario, ma il repository non soddisfa ancora il target zero-legacy.
- Risultato atteso: tutti i file Swift non-UI fuori dalla UI/binding/bootstrap Apple allowlisted devono essere eliminati o sostituiti da implementation Rust; lo strict audit deve terminare con exit code `0`.
- Causa probabile: il cutover e' stato gestito per tranche incrementalmente, ma il backlog legacy e' ancora molto ampio in piu' domini e il gate finale repo-wide non era ancora esercitabile con un comando strict dedicato.
- Scope consentito:
  - `Native/AppCoreRust/src/bin/rust_cutover_guard.rs`
  - `docs/migration/RUST_CUTOVER_AUDIT_2026-03-16.md`
  - `docs/bugs/`
  - `docs/changelog/`
- Non-scope:
  - migrazione completa dei domini `App`, `Engine`, `Tools` e `Tests`
  - refactor dei panel UI
  - attivazione automatica del fail hard repo-wide dentro la pipeline corrente
- Moduli confinanti da verificare:
  - crate `Native/AppCoreRust`
  - domini `App/SoloCodeApp/Sources/Panels/CodeReview`
  - `Engine/CoderEngine/Sources/CodeReview`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`
- Test da aggiungere o aggiornare:
  - unit test del binario `rust_cutover_guard` per la modalita' `--fail-on-legacy-non-ui`
- Strategia di fix minimo:
  - non fingere il cutover completo
  - introdurre uno strict audit ripetibile che fallisce quando esiste qualunque Swift non-UI legacy
  - fissare un baseline documentato per il workspace e per il solo dominio review
- Verifica post-fix:
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist Config/validation/rust-cutover-swift-allowlist.txt --fail-on-legacy-non-ui --format text` deve fallire finche' il debito resta presente
  - audit review-scope documentato in `docs/migration/RUST_CUTOVER_AUDIT_2026-03-16.md`
- Commit previsto: `fix(rust-cutover): add strict audit mode and baseline report`

## Stato osservato il 2026-03-16
- Workspace completo:
  - `1610` file Swift scansionati
  - `113` allowlisted UI/bootstrap
  - `1497` legacy non-UI
- Dominio review:
  - `117` file Swift scansionati
  - `45` allowlisted UI
  - `72` legacy non-UI
- Breakdown review:
  - `App/SoloCodeApp/Sources/Panels/CodeReview`: `19`
  - `App/SoloCodeApp/Sources/App/Bootstrap/Sections/CodeReview`: `6`
  - `Engine/CoderEngine/Sources/CodeReview`: `29`
  - `Engine/CoderEngine/Sources/VerifiedFindingsCore`: `14`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`: `4`

## Nota operativa
- Questo finding non dichiara il cutover completato.
- Questo finding rende invece il gap misurabile, ripetibile e pronto per essere drenato per tranche senza ambiguita' sul target finale.
