# 2026-03-12 — Review chat findings rust-only merge

## Scope
- sync dei `review_findings` strutturati dalla chat review
- rimozione del fallback dedup Swift nel panel

## Modifiche
- rimosso `mergeChatFindingsFallback(...)` dal panel review
- lasciato `syncStructuredFindingsFromChatResponse(...)` dipendere solo dal merge Rust
- aggiunta copertura Rust su `insertedCount` per nuovi finding chat

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`

## Note
- la regressione app-side rimane coperta dal test di session scoping gia' presente; questa tranche non cambia la UI del panel
