# P1 — Raw update differiti potevano arrivare dopo la finalizzazione del review panel

## Bug Fix Record
- Categoria: A
- Bug: i raw update del review panel venivano differiti con `DispatchQueue.main.async`, ma `finishPanelActionOutput(...)` e `failPanelActionOutput(...)` finalizzavano subito il messaggio, aprendo una race tra enqueue e finalize.
- Sintomo: gli ultimi blocchi `Thinking`/`Planned Work`/`Activity` potevano sparire dal messaggio finale oppure l'ultimo `assistant_update` poteva ricreare una bubble response in stato streaming dopo la completion.
- Impatto: transcript finale incoerente, output finale mancante o duplicato nel panel chat.
- Gravità: alta
- Steps to reproduce:
  1. Aprire un review run nel panel.
  2. Emettere un raw event poco prima della completion (`reasoning`, `review-worker-plan` o `assistant_update`).
  3. Finalizzare immediatamente il run.
- Risultato attuale: la presentation poteva essere congelata prima dell'ultimo update o la response bubble poteva essere ricreata tardi.
- Risultato atteso: tutti i raw update già schedulati devono essere flushati prima della finalizzazione; eventuali late update su un run già chiuso devono aggiornare uno stato finale coerente, non ricreare streaming bubble.
- Causa probabile: mancanza di una coda per le mutazioni differite del review run e assenza di flush esplicito in `finishPanelActionOutput(...)`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
- Non-scope:
  - redesign del rendering chat
  - refactor del provider panel
- Moduli confinanti da verificare:
  - `CodeReviewPanelChatStateDeferralTests`
  - split bubble response/verdict
- Test da aggiungere o aggiornare:
  - regressione su flush dei raw section update prima della finalize
  - regressione su mancata ricreazione della response bubble dopo finish
- Strategia di fix minimo:
  - introdurre una coda per le mutazioni differite per `activityId`
  - flushare la coda in `finishPanelActionOutput(...)` e `failPanelActionOutput(...)`
  - mantenere la response bubble non streaming anche per late update
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests`
- Commit previsto: `fix(review-panel): flush deferred raw output before finalizing`

## Evidenza
- i nuovi test riproducono sia il caso dei section update tardivi sia il caso dell'ultimo `assistant_update`
- il fix resta confinato al layer panel store, senza cambiare i provider
