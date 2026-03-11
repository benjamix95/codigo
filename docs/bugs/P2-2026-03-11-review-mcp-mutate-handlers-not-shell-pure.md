# P2 — Handler MCP mutate review/security/bughunter non ancora shell pure

## Sintomo
Gli handler MCP mutate lato Swift continuavano a contenere branching locale per validazione ed enqueue dei comandi review/security/bughunter.

## Impatto
- semantica duplicata fuori dal core Rust
- rischio di drift tra tool MCP e motore review
- maggiore complessità nei router Swift del server MCP

## Fix applicato
- gli handler mutate review/security/bughunter usano il risultato Rust come gate principale
- Swift si limita a fare enqueue minimo sul command/shared state già Rust-backed
- in assenza del core Rust, i path mutate falliscono esplicitamente invece di rieseguire business logic locale

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- validazione Swift soggetta al problema ambientale intermittente del runner Xcode su `IDESimulatorFoundation/CoreSimulator`
