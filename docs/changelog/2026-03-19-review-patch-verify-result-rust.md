# 2026-03-19 — Review patch verify result in Rust

## Modifiche
- aggiunto builder Rust `review_patch::verify_result`
- esposto endpoint FFI `review_core_patch_build_verify_result`
- `ReviewPatchWorkflowService.verifyPatch(...)` continua a eseguire `git apply --check` in Swift, ma il risultato finale dell’artifact viene derivato dal review core Rust
- aggiunti test Rust sul builder del verify result
- aggiunti test Swift sul path verified e sul fail-closed quando il runtime verify result non è disponibile

## Motivazione
- togliere a Swift un altro pezzo di ownership del patch lifecycle e preparare il passaggio successivo su `apply_patch`

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
