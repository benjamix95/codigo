# 2026-03-11 — Review MCP mutate shell tranche

## Scope
- riduzione degli handler MCP mutate review/security/bughunter a shell più pura

## Modifiche
- aggiornato `CodeReviewHandler+PatchWorkflow.swift` per usare il risultato Rust come gate di validazione e fare solo enqueue minimale
- aggiornato `SecurityHandler+Routing.swift` con lo stesso pattern
- aggiornato `BugHunterHandler+Commands.swift` per allineare il path mutate al gate Rust
- rimosso branching business-side residuo dagli handler mutate quando il core Rust è disponibile

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- validazione Xcode intermittente bloccata da plug-in host-side `IDESimulatorFoundation/CoreSimulator`
