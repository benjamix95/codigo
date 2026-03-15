# P1 — `CodeReviewAuditService.runTool(...)` instradava i tool security avanzati sul backend sbagliato

## Categoria
- A — Critico

## Bug
- I tool review security avanzati (`securityDataflow`, `securityAuthz`, `securityCrypto`, `securityDeserialization`, `securitySurface`, `securitySupplyChain`) venivano instradati dal `runTool(...)` verso il bridge generico Rust/unsupported path invece che verso il fallback Swift locale previsto.

## Sintomo
- `CodeReviewAuditAdvancedTests` falliva su:
  - `testSecurityDataflowDetectsSourceSinkPattern`
  - `testUnsupportedToolReturnsEmptyWithPositiveDuration`

## Impatto
- Gli audit review security avanzati potevano restituire zero finding o summary sbagliata.
- Il dominio review engine perdeva il contratto di dispatch corretto tra tool avanzati locali e backend Rust.

## Scope consentito
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService.swift`
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+SecurityAdvanced.swift`
- `Engine/CoderEngine/Sources/CodeReview/Audit/CodeReviewAuditService+Security.swift`
- `Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift`

## Non-scope
- nuovi tool audit
- MCP review
- refactor del resto del pipeline review

## Strategia di fix minimo
- correggere il dispatch di `runTool(...)` per i tool security avanzati
- classificare i tool ignoti come `unsupported` anche senza bridge disponibile
- rimuovere il file Swift legacy `CodeReviewAuditService+Security.swift`, lasciando in `SecurityAdvanced` solo la porzione dependency/supply-chain ancora usata

## Moduli confinanti da verificare
- `CodeReviewAuditAdvancedTests`
- `ReviewPipelineCoordinator+Runtime`
- `SecurityStage`

## Verifica post-fix
- `build-for-testing` target `CoderEngineTests-Debug`
- suite completa `CodeReviewAuditAdvancedTests`
- `rust_cutover_boundary` verde sul prefisso `Engine/CoderEngine/Sources/CodeReview`

## Commit previsto
- `fix(review): restore advanced audit dispatch and remove security fallback file`
