# 2026-03-12 — Review MCP start rust preflight

## Scope
- preflight MCP dei tool `review_start`, `security_start`, `bughunter_start`
- riduzione del fallback handler-centric Swift

## Modifiche
- reso obbligatorio il preflight Rust per `review_start`
- reso obbligatorio il preflight Rust per `security_start`
- reso obbligatorio il preflight Rust per `bughunter_start`
- rimosse le validazioni Swift duplicate che il dispatcher Rust gia' copre
- aggiunta regressione dedicata per `bughunter_start` con `source_kind` invalido

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`

## Note
- il contratto utente dei tool resta invariato: Rust decide il preflight, Swift esegue l’enqueue effettivo
