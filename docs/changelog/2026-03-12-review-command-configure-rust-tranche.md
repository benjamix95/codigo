# 2026-03-12 — Review command configure Rust tranche

## Scope
- comando `review_configure` per sessioni live e snapshot persistiti
- boundary Rust `review_core_command_mutate_snapshot`

## Modifiche
- estratto il supporto config del review command Rust in moduli dedicati (`config`, `mutator_configure`, `mutator_support`)
- esteso il mutator Rust per `configure`, con ritorno della config normalizzata e dell'evento `config_updated`
- aggiunto `SessionConfig.reviewCommandPayload` per serializzare una config canonica verso il boundary Rust
- aggiornato `ReviewSessionRegistry.updateConfig` per usare il mutator Rust invece di `state.updateConfig(...)`
- aggiornato il command loop review dell'app per usare lo stesso path Rust anche sul fallback snapshot-only
- aggiunte regressioni Rust, engine e app-side per `configure`

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml --quiet`
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --quiet`

## Note
- la validazione macOS via `xcodebuildmcp` resta da eseguire fuori da questa sessione, perche' il tool non e' disponibile qui
- il cutover della pipeline review e del runtime provider resta fuori scope per questa tranche
