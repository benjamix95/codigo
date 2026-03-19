# 2026-03-19 — Review patch apply result in Rust

## Modifiche
- aggiunto builder Rust `review_patch::apply_result`
- esposto endpoint FFI `review_core_patch_build_apply_result`
- `ReviewPatchWorkflowService.applyPatch(...)` continua a eseguire `git apply --3way` e validation in Swift, ma il risultato finale dell’artifact applicato viene derivato dal review core Rust
- aggiunti test Rust sul builder `apply_result`
- aggiunti test Swift sul risultato applicato e sul fail-closed quando il runtime `apply_result` non è disponibile

## Motivazione
- togliere a Swift un altro pezzo di ownership del patch lifecycle e preparare il passaggio successivo su rollback/revalidate o sull’esecuzione patch completa

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
