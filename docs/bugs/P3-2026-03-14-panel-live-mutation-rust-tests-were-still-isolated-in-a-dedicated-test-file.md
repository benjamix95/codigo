# P3 — I test `CodeReviewPanelLiveMutationRustTests` erano ancora isolati in un file review app dedicato

## Categoria
- C — Minore / cosmetico

## Bug
- La suite review panel app manteneva ancora un file XCTest standalone solo per il path di live mutation Rust.

## Impatto
- Debito di cutover review test-side ancora presente nel target app.

## Scope consentito
- `Tests/SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests.swift`
- `Tests/SoloCodeAppTests/ReviewPatchWorkflowServiceTests.swift`

## Strategia di fix minimo
- Consolidare la classe `CodeReviewPanelLiveMutationRustTests` in `ReviewPatchWorkflowServiceTests.swift` mantenendo la classe separata per la discoverability.

## Verifica post-fix
- `SoloCodeAppTests/CodeReviewPanelLiveMutationRustTests`

## Commit previsto
- `test(review): fold panel live mutation tests into patch workflow`
