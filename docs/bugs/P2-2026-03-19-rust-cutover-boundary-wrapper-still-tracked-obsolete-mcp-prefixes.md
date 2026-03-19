# P2 — il wrapper del boundary Rust cutover tracciava ancora prefissi MCP obsoleti

## Categoria
- `B` importante ma non bloccante

## Bug
- Il wrapper [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh) continuava a monitorare `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CodeReview`, mentre il backlog MCP reale finale è sotto `ReviewBootstrap`, `Security` e `BugHunter`.

## Sintomo
- Il guard lanciato manualmente sul binario Rust vedeva il backlog corretto, ma lo script wrapper non rappresentava più i prefissi MCP finali.

## Impatto
- Misurazione incompleta dell’ultima macro-tranche.
- Rischio di pensare chiuso il backlog MCP finale quando il wrapper non lo stava nemmeno contando.

## Gravità
- `P2`

## Steps to reproduce
1. Aprire [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh).
2. Guardare `REVIEW_CUTOVER_PREFIXES`.
3. Osservare che manca `ReviewBootstrap`, `Security`, `BugHunter`.

## Risultato attuale
- Lo script non rifletteva più il perimetro MCP reale del cutover.

## Risultato atteso
- Il wrapper deve usare i prefissi MCP reali ancora bloccanti.

## Causa probabile
- Il cutover MCP è avanzato per tranche ma il wrapper shell era rimasto fermo a un prefisso storico.

## Scope consentito
- [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh)
- `docs/bugs`
- `docs/changelog`

## Non-scope
- Modifiche runtime MCP
- Allowlist UI
- Core review Rust

## Moduli confinanti da verificare
- invocazione manuale del `rust_cutover_guard`

## Test da aggiungere o aggiornare
- nessun test dedicato; verifica manuale del comando wrapper/binario

## Strategia di fix minimo
- sostituire il prefisso MCP obsoleto con i tre prefissi reali finali

## Verifica post-fix
- `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist /Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt --candidate-files "<csv>" --enforce-legacy-zero-prefixes "Engine/CoderEngine/Sources/CodeReview,Engine/CoderEngine/Sources/VerifiedFindingsCore,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter" --include-missing-candidate-files --format json`

## Commit previsto
- `chore(boundary): track final mcp cutover prefixes`
