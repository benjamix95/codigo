# P1 - Mancava un guardrail di repository per bloccare nuovi file Swift non-UI durante il cutover Rust

## Bug Fix Record
- Categoria: A - Critico
- Bug: il repository non aveva un controllo automatico che impedisse l'introduzione di nuovi file Swift non-UI mentre l'obiettivo architetturale e' spostare tutto il runtime fuori dalla UI in Rust.
- Sintomo: una PR poteva aggiungere nuova business logic Swift in `App/`, `Engine/` o test non-UI senza nessun fallimento automatico della pipeline.
- Impatto: drift continuo del perimetro, regressioni del piano di migrazione, impossibilita' di congelare il boundary tra UI Swift e runtime Rust.
- Gravita': alta
- Steps to reproduce:
  1. Aggiungere un nuovo file Swift non-UI, ad esempio `App/SoloCodeApp/Sources/Runtime/NewLogic.swift`.
  2. Eseguire la pipeline di validazione attuale.
  3. Osservare che build/test potevano passare senza segnalare la violazione del boundary.
- Risultato attuale: il repository deve consentire solo nuovi file Swift UI/binding/bootstrap esplicitamente allowlisted; i nuovi file Swift non-UI devono fallire in validazione.
- Risultato atteso: esiste un audit Rust del boundary con allowlist versionata, integrato in CI e nello script `solocode-validate`.
- Causa probabile: la migrazione a Rust e' avanzata per tranche di dominio, ma il controllo di perimetro del repository non era ancora stato formalizzato.
- Scope consentito:
  - `Native/AppCoreProtocol`
  - `Native/AppCoreRust`
  - `Config/validation/rust-cutover-swift-allowlist.txt`
  - `scripts/solocode-validate`
  - `scripts/validate_rust_cutover_boundary.sh`
  - `.github/workflows/validation.yml`
  - `.gitignore`
- Non-scope:
  - migrazione completa del review panel
  - cutover di `Pipeline`, `Tools`, `Providers` e `PersistenceCore`
  - rimozione immediata di tutti i file Swift legacy non-UI gia' presenti
- Moduli confinanti da verificare:
  - workspace Rust sotto `Native/`
  - pipeline di validazione CI
  - directory `Config/validation`
- Test da aggiungere o aggiornare:
  - test Rust del dispatch `AppCoreRequest::BoundaryAudit`
  - test classifier per file allowlisted UI
  - test classifier per nuove violazioni Swift non-UI
- Strategia di fix minimo:
  - introdurre un crate Rust piccolo e isolato per il boundary audit
  - esporre DTO versionati in `AppCoreProtocol`
  - integrare il guardrail nella validation senza forzare ancora il fail sui file legacy gia' esistenti
- Verifica post-fix:
  - `cargo test --manifest-path Native/AppCoreRust/Cargo.toml`
  - `scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files <changed-files>`
- Commit previsto: `feat(rust-cutover): add repository boundary guard and app core foundation`
