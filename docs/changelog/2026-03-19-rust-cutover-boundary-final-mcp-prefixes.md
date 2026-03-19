# 2026-03-19 — Rust cutover boundary sui prefissi MCP finali

## Modifiche
- aggiornato [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh) per monitorare i prefissi MCP reali ancora legacy:
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security`
  - `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter`

## Motivazione
- riallineare il wrapper shell al backlog MCP reale dell’ultima macro-tranche, evitando misurazioni parziali o obsolete

## Verifica
- `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist /Users/benjaminstoica/SoloCode/Config/validation/rust-cutover-swift-allowlist.txt --candidate-files "<csv>" --enforce-legacy-zero-prefixes "Engine/CoderEngine/Sources/CodeReview,Engine/CoderEngine/Sources/VerifiedFindingsCore,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/ReviewBootstrap,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security,Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/BugHunter" --include-missing-candidate-files --format json`
