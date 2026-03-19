# 2026-03-19 — Review patch PR e merge results in Rust

## Modifiche
- aggiunti builder Rust `review_patch::open_pr_result`, `review_patch::merge_result` e `review_patch::resolve_conflicts_result`
- esposti endpoint FFI `review_core_patch_build_open_pr_result`, `review_core_patch_build_merge_result` e `review_core_patch_build_resolve_conflicts_result`
- `ReviewPatchWorkflowService.swift` e `ReviewPatchWorkflowService+Merge.swift` continuano a eseguire il lavoro Git/PR in Swift, ma il risultato finale dell’artifact per `open_pr`, `merge_pr` e `resolve_conflicts` viene derivato dal review core Rust
- aggiunti test Rust sui nuovi builder
- aggiunti test Swift sui nuovi result bridge e sul fail-closed quando i runtime non sono disponibili

## Motivazione
- togliere a Swift l’ultimo blocco di result shaping del patch lifecycle e lasciare solo l’ownership residua dell’upsert canonico dello snapshot come ultimo punto da chiudere nella tranche 4

## Verifica
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
