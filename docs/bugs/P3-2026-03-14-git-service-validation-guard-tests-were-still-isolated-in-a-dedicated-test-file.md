# P3 — I test `GitServiceValidationGuardTests` erano ancora isolati in un file XCTest dedicato

## Categoria
- C — Minore / cosmetico

## Bug
- Un file test-side standalone per il guard di commit git restava separato nonostante il perimetro di test git/persistence fosse già presente.

## Impatto
- Un file Swift non-UI in più nel target app.

## Scope consentito
- `Tests/SoloCodeAppTests/GitServiceValidationGuardTests.swift`
- `Tests/SoloCodeAppTests/CheckpointGitStoreTests.swift`

## Strategia di fix minimo
- Consolidare `GitServiceValidationGuardTests` in `CheckpointGitStoreTests.swift` mantenendo una classe XCTest separata.

## Verifica post-fix
- `SoloCodeAppTests/GitServiceValidationGuardTests`
- `SoloCodeAppTests/CheckpointGitStoreTests`

## Commit previsto
- `test(app): fold git validation guard tests into checkpoint store`
