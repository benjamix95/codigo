# P3 — I test `BugHunterWorkflowServiceTests` erano ancora isolati in un file review dedicato

## Categoria
- C — Minore / cosmetico

## Bug
- La suite review engine conservava ancora un file XCTest standalone solo per un singolo caso `BugHunterWorkflowService`.

## Sintomo
- Un file Swift review test-side dedicato restava nel perimetro legacy non-UI.

## Impatto
- Debito di cutover review non ridotto.
- Struttura test review più frammentata del necessario.

## Scope consentito
- `Tests/CoderEngineTests/CodeReview/BugHunterWorkflowServiceTests.swift`
- `Tests/CoderEngineTests/CodeReview/CodeReviewMultiSwarmProviderTests+TaskExtraction.swift`

## Strategia di fix minimo
- Consolidare la classe `BugHunterWorkflowServiceTests` in un file review XCTest già esistente mantenendo una classe separata per la discoverability.

## Verifica post-fix
- `CoderEngineTests/BugHunterWorkflowServiceTests`

## Commit previsto
- `test(review): fold bughunter workflow tests into task extraction`
