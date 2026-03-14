# P2 - La suite audit advanced resta rossa su path runtime non correlati alla tranche

## Bug Fix Record
- Categoria: B
- Bug: `CodeReviewAuditAdvancedTests` continua a fallire su `securityDataflow`, `bugTestImpact` e `unsupported tool` anche quando la tranche tocca solo `correlateResults` / `runProfile`.
- Sintomo: la suite completa fallisce, ma il subset dei test correlati alla tranche passa.
- Impatto: il file audit puo' essere drenato solo usando subset mirati finché i path runtime non vengono diagnosticati separatamente.
- Gravità: P2
- Steps to reproduce:
  1. Eseguire `xcodebuild test-without-building ... -only-testing:CoderEngineTests/CodeReviewAuditAdvancedTests`.
  2. Osservare failure su `testSecurityDataflowDetectsSourceSinkPattern`, `testBugTestImpactFlagsPublicSymbolsWithoutTests` e `testUnsupportedToolReturnsEmptyWithPositiveDuration`.
- Risultato attuale: la suite completa resta rumorosa su comportamenti non toccati dalla tranche correlation.
- Risultato atteso: la suite completa dovrebbe essere affidabile come gate unico dell'area audit.
- Causa probabile: instabilità preesistente nel path runtime / tool execution dell'audit service.
- Scope consentito per il futuro fix:
  - `Engine/CoderEngine/Sources/CodeReview/Audit`
  - `Tests/CoderEngineTests/CodeReview/CodeReviewAuditAdvancedTests.swift`
- Non-scope:
  - panel UI
  - verified findings
  - MCP handler
- Strategia di fix minimo:
  - non inclusa in questa tranche; bug registrato per analisi dedicata
