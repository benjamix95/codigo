# P2 — `textDelta` / `textReplace` tardivi mutano il transcript review dopo `finish`

## Bug Fix Record
- Categoria: B
- Bug: la guardia introdotta sul transcript finalizzato copriva solo `assistant_update` raw e non il path principale `StreamEvent.textDelta` / `.textReplace`.
- Sintomo: un provider che emetteva update tardivi sullo stream poteva ancora ricreare o sovrascrivere la response bubble dopo `finishPanelActionOutput(...)`.
- Impatto: transcript review incoerente nonostante il run sia già stato finalizzato.
- Gravità: media
- Steps to reproduce:
  1. Inviare una `textReplace` o `textDelta` finale.
  2. Finalizzare il run.
  3. Ricevere un ulteriore evento `textReplace` o `textDelta` sullo stesso `activityId`.
- Risultato attuale: la response bubble poteva cambiare anche dopo la finalize.
- Risultato atteso: tutti gli update di risposta devono essere ignorati una volta marcato il run come finito.
- Causa probabile: la guardia `finishedReviewRunActivityIds` era applicata solo nel formatter raw.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
- Non-scope:
  - redesign del protocollo stream provider
  - sequence number provider-side
- Moduli confinanti da verificare:
  - response bubble split/finalize
  - review panel transcript tests
- Test da aggiungere o aggiornare:
  - regressioni su `textReplace` e `textDelta` dopo `finish`
- Strategia di fix minimo:
  - applicare la guardia `finishedReviewRunActivityIds` anche al path `streamPanelActionOutput(...)`
- Verifica post-fix:
  - `CodeReviewPanelChatStateDeferralTests`
- Commit previsto: `fix(review-panel): ignore late stream updates after finish`
