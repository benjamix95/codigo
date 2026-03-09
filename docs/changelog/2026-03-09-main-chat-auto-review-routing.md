# 2026-03-09 — Main chat auto review routing

## Cosa cambia
- la main chat riconosce richieste esplicite di:
  - code review
  - security review / security audit
  - bug hunt / regressioni / crash hunt
- quando l’intento è esplicito, il composer instrada il turno verso il runtime code review shared senza costringere l’utente a cambiare manualmente modalità
- il prompt utente viene wrappato con `ReviewPanelCoordinator.combinedPrompt(...)`, mantenendo la richiesta originale come istruzione aggiuntiva
- i prompt normali e gli slash command restano invariati

## File principali
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ComposerUI/ChatPanelView+PartH_CodeReviewModes.swift`
- `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartL_SendMessage.swift`
- `Tests/SoloCodeAppTests/AutoCodeReviewRoutingTests.swift`

## Test
- `SoloCodeAppTests/AutoCodeReviewRoutingTests`
- `SoloCodeAppTests/CodeReviewPanelValidationTests`
- `SoloCodeAppTests/PipelineIntegrationVerifiedFindingsTests`

## Note
- fix confinato al routing del composer nella main chat
- nessuna modifica al core `VerifiedFindings`
- il trigger resta intenzionale: parte solo su richieste review/bug/security chiaramente esplicite, per non dirottare richieste generiche
