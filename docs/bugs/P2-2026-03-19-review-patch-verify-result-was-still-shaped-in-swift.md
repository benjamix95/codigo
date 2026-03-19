# P2 — review patch verify result ancora modellato in Swift

## Categoria
- `B` importante ma non bloccante

## Bug
- L’esito di `verify_patch` veniva ancora trasformato in stato artifact locale in Swift dopo `git apply --check`.

## Sintomo
- `ReviewPatchWorkflowService.verifyPatch(...)` decideva localmente:
  - `status = .verified` / `.conflict`
  - `verifyStatus = .verified` / `.failed`
  - `conflicts`
  - `applyMessage`

## Impatto
- Ownership ancora sdoppiata sul lifecycle patch.
- Il runtime patch Rust orchestrava i passi ma non il risultato canonico della verifica.
- Il batch successivo su `apply_patch` sarebbe partito da una base ancora Swift-owned.

## Gravità
- `P2`

## Steps to reproduce
1. Eseguire `verify_patch` su un artifact patch.
2. Osservare che prima del fix `git apply --check` veniva eseguito in Swift e anche il risultato finale veniva modellato in Swift.

## Risultato attuale
- Prima del fix, Rust non partecipava allo shaping del risultato di verifica.

## Risultato atteso
- L’esecuzione `git apply --check` può restare Swift in questo batch, ma il risultato canonico deve essere derivato da Rust.

## Causa probabile
- Il cutover patch era fermo a planner, runtime state e prepare context; il verify result era ancora un post-processing locale.

## Scope consentito
- `Native/RustCore/src/review_patch/{verify_result.rs,models.rs,mod.rs}`
- `Native/RustCore/src/ffi/review_patch.rs`
- `App/SoloCodeApp/Sources/CodeReview/Services/ReviewPatchWorkflowService.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Non-scope
- Porting di `apply_patch`, `rollback_patch`, `merge_pr`, `resolve_conflicts`
- MCP ownership
- UI panel

## Moduli confinanti da verificare
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Test da aggiungere o aggiornare
- test Rust del builder `verify_result`
- test Swift Rust-gated per il risultato verified
- test fail-closed se il runtime Rust del verify result non è disponibile

## Strategia di fix minimo
- aggiungere builder Rust per il risultato di `verify_patch`
- fare chiamare quel builder a `ReviewPatchWorkflowService.verifyPatch(...)`
- lasciare in Swift solo il `git apply --check` nel batch corrente

## Verifica post-fix
- `cargo test --manifest-path Native/RustCore/Cargo.toml`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ReviewPatchWorkflowServiceTests`

## Commit previsto
- `refactor(review-patch): derive verify result in rust`
