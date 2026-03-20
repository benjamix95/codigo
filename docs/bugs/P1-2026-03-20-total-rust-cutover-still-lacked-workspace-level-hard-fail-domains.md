# P1 - Il cutover totale a Rust non aveva ancora domini hard-fail a livello workspace

## Bug Fix Record
- Categoria: A
- Bug: il repository aveva guardrail duri solo su `review` e `main chat`, ma nessun tranche gate workspace-level sui domini Swift non-UI gia' chiaramente business logic.
- Sintomo:
  - il strict audit workspace mostrava ancora `1310` file Swift legacy non-UI, ma il guard automatico non promuoveva a hard-fail domini come `Infrastructure`, `Tools`, `CodebaseIndex`, `ProviderBackends`, `Accounts`, `Git`, `Planning`, `Debug`
  - fuori da `review` e `main chat` un diff poteva ancora entrare in domini non-UI pesanti senza obbligo di riduzione backlog
- Impatto: il piano di cutover totale a Rust restava non enforceable a livello workspace; il debito strutturale totale continuava a essere solo inventario, non invariante di validation.
- Gravita': alta
- Steps to reproduce:
  1. eseguire il strict audit workspace con `rust_cutover_guard --fail-on-legacy-non-ui`
  2. osservare il backlog pesante su `Accounts`, `Debug`, `Git`, `Infrastructure`, `Tools`, `CodebaseIndex`, `ProviderBackends`, `Providers`, `Validation`
  3. modificare un file Swift in uno di questi domini e verificare che, prima del fix, il guard automatico non attivava un tranche gate dedicato
- Risultato attuale: il workspace non aveva ancora hard-fail domains globali abbastanza ampi per sostenere un vero cutover totale.
- Risultato atteso: i domini non-UI gia' netti devono entrare automaticamente nel tranche gate quando un diff li tocca.
- Causa probabile: il boundary guard e' cresciuto per domini verticali (`review`, poi `main chat`), ma non era ancora stato generalizzato al cutover workspace-level.
- Scope consentito:
  - [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh)
  - `docs/migration`
  - `docs/bugs`
  - `docs/changelog`
- Non-scope:
  - attivazione hard-fail su directory miste UI/business come `Panels`, `Services`, `Tasking`, `Settings`, `Editor`, `Swarm`
  - nuova migrazione di runtime business in Rust
- Moduli confinanti da verificare:
  - `rust_cutover_guard`
  - `solocode-validate`
  - strict audit workspace
- Test da aggiungere o aggiornare:
  - smoke manuale con `validate_rust_cutover_boundary.sh` su un file candidato sotto un prefisso totale
- Strategia di fix minimo:
  - introdurre una lista di prefissi hard-fail globali solo per i domini non-UI gia' chiaramente separati
  - documentare baseline e top domini in un report canonico workspace-level
- Verifica post-fix:
  - `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist Config/validation/rust-cutover-swift-allowlist.txt --fail-on-legacy-non-ui --format text`
  - `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift" --format text`
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "scripts/validate_rust_cutover_boundary.sh,docs/bugs/P1-2026-03-20-total-rust-cutover-still-lacked-workspace-level-hard-fail-domains.md,docs/changelog/2026-03-20-total-rust-cutover-workspace-phase0-guardrail.md,docs/migration/RUST_CUTOVER_WORKSPACE_BASELINE_2026-03-20.md" --format text`
- Commit previsto: `fix(validation): add workspace rust cutover hard-fail domains`

## Effetto osservato
- il cutover totale a Rust smette di essere solo un obiettivo architetturale e diventa una regola enforceable sui domini non-UI gia' netti
- i domini misti restano volutamente fuori finche' non vengono spezzati in modo piu' pulito
