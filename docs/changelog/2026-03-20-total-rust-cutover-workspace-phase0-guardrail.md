# 2026-03-20 — Fase 0 workspace-level per il cutover totale a Rust

## Modifiche
- aggiornato [validate_rust_cutover_boundary.sh](/Users/benjaminstoica/SoloCode/scripts/validate_rust_cutover_boundary.sh) con un set di prefissi hard-fail workspace-level per i domini Swift non-UI gia' chiaramente separati
- aggiunto il bug record [P1-2026-03-20-total-rust-cutover-still-lacked-workspace-level-hard-fail-domains.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-20-total-rust-cutover-still-lacked-workspace-level-hard-fail-domains.md)
- documentata la baseline strict workspace in [RUST_CUTOVER_WORKSPACE_BASELINE_2026-03-20.md](/Users/benjaminstoica/SoloCode/docs/migration/RUST_CUTOVER_WORKSPACE_BASELINE_2026-03-20.md)

## Risultato
- il cutover totale a Rust ha ora una baseline workspace-level reale:
  - `1615` Swift scansionati
  - `305` allowlist
  - `1310` legacy non-UI
- i domini non-UI gia' netti non possono piu' essere modificati senza entrare nel tranche gate del cutover totale
- le directory ancora miste UI/business restano esplicitamente fuori dal guard globale finche' non vengono spezzate

## Verifica
- `cargo run --quiet --manifest-path Native/AppCoreRust/Cargo.toml --bin rust_cutover_guard -- --workspace /Users/benjaminstoica/SoloCode --allowlist Config/validation/rust-cutover-swift-allowlist.txt --fail-on-legacy-non-ui --format text`
- `./scripts/validate_rust_cutover_boundary.sh --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --files "Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustBackend.swift" --format text`
