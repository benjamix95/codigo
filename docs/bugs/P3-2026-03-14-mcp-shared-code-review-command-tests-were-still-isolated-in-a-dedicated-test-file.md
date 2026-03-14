# P3 — I test `MCPSharedCodeReviewCommandsTests` erano ancora isolati in un file review dedicato

## Categoria
- C — Minore / cosmetico

## Bug
- La suite review engine manteneva ancora un file XCTest standalone per i comandi MCP condivisi review.

## Impatto
- Debito di cutover review test-side ancora presente.

## Scope consentito
- `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewCommandsTests.swift`
- `Tests/CoderEngineTests/CodeReview/CodeReviewSessionStateTests+TerminalLifecycle.swift`

## Strategia di fix minimo
- Consolidare la classe `MCPSharedCodeReviewCommandsTests` in un file review XCTest già esistente senza cambiare i nomi delle classi.

## Verifica post-fix
- `CoderEngineTests/MCPSharedCodeReviewCommandsTests`

## Commit previsto
- `test(review): fold shared mcp command tests into terminal lifecycle`
