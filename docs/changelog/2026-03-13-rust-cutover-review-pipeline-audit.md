# 2026-03-13 - Rust cutover review pipeline/audit

## Modifiche
- rimosso il fallback Swift completo da `ReviewPipelineCoordinator`; la pipeline review richiede ora esplicitamente il core Rust
- aggiornato `CodeReviewAuditService` per usare solo il bridge Rust sui tool audit non-meta
- i tool audit non ancora coperti dal crate Rust non eseguono piu' business logic Swift locale: ritornano un risultato esplicito `unsupported` o `unavailable`
- aggiornati i test della pipeline review per caricare il core Rust quando disponibile e per verificare il failure esplicito quando il core viene disabilitato

## Validazione
- `cargo test --manifest-path Native/RustCore/Cargo.toml -- --nocapture`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`: build compilativa verde del target engine dopo la rimozione dei fallback
- l'esecuzione `xcodebuild test` sul bundle `CoderEngineTests.xctest` in questa macchina resta soggetta al problema ambientale gia' noto di code-sign / system policy

## Impatto
- il motore review non puo' piu' nascondere l'assenza del runtime Rust dietro una pipeline Swift legacy
- l'audit review rende espliciti i gap di copertura Rust invece di mantenere ownership duplicata
