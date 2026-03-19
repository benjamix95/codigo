# 2026-03-19 - Review patch revalidate/rollback results in Rust

## Cosa cambia
- `ReviewPatchWorkflowService+ApplyLifecycle.swift` non decide piu` localmente il risultato finale di `revalidate_finding` e `rollback_patch`.
- Il review core Rust espone i nuovi builder:
  - `review_core_patch_build_revalidate_result`
  - `review_core_patch_build_rollback_result`
- Il path Swift fallisce closed se il runtime Rust non e` disponibile.

## Dettagli
- `revalidatePatchResult(...)` deriva da Rust:
  - `status`
  - `validationRunId`
  - `validationStatus`
  - `validationSummary`
  - `applyMessage`
- `rollbackPatchResult(...)` deriva da Rust:
  - `status`
  - `applyMessage`
- Il bridge FFI di `revalidate` ora segnala esplicitamente errore su request invalide o schema non supportato.

## Test
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`
