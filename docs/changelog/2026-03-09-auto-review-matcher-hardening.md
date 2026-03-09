# 2026-03-09 — Auto review matcher hardening

## Cosa cambia
- il matcher automatico della main chat riconosce meglio richieste review meno esplicite ma comunque operative:
  - vulnerabilità nelle modifiche
  - regressioni/crash nelle modifiche
  - audit su diff/patch/commit/branch
- sono stati aggiunti guardrail contro i falsi positivi su richieste descrittive o teoriche
- corretto il falso positivo sul token `pr`, che intercettava parole come `progetto`

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_CodeReviewModes.swift`
- `Tests/SoloCodeAppTests/AutoCodeReviewRoutingTests.swift`

## Test
- `SoloCodeAppTests/AutoCodeReviewRoutingTests`
- `SoloCodeAppTests/CodeReviewPanelValidationTests`
- `SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`

## Note
- fix confinato all’heuristica di riconoscimento intent nella composer main chat
- nessuna modifica al core `VerifiedFindings` o al runtime review shared
