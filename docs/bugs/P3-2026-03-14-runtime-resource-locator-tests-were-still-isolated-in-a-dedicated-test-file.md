# P3 — I test `RuntimeResourceLocatorTests` erano ancora isolati in un file XCTest dedicato

## Categoria
- C — Minore / cosmetico

## Bug
- Un file test-side standalone per `RuntimeResourceLocator` restava separato pur potendo vivere nello stesso perimetro dei test provider review.

## Impatto
- Un file Swift non-UI in più nel target app.

## Scope consentito
- `Tests/SoloCodeAppTests/RuntimeResourceLocatorTests.swift`
- `Tests/SoloCodeAppTests/ProviderFactoryCodeReviewTests.swift`

## Strategia di fix minimo
- Consolidare `RuntimeResourceLocatorTests` in `ProviderFactoryCodeReviewTests.swift` mantenendo il blocco `Testing` separato.

## Verifica post-fix
- `SoloCodeAppTests/ProviderFactoryCodeReviewTests`
- `SoloCodeAppTests/RuntimeResourceLocatorTests`

## Commit previsto
- `test(review): fold runtime resource locator tests into provider factory`
