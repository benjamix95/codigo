# P1 — Late assistant_update dopo finish corrompe il transcript review

## Bug Fix Record
- Categoria: B
- Bug: un `assistant_update` ricevuto dopo `finishPanelActionOutput(...)` poteva mutare una response bubble già finalizzata.
- Sintomo: risposta finale e verdict potevano diventare stantii o incoerenti dopo update tardivi.
- Impatto: transcript review non affidabile dopo la completion.
- Gravità: alta
- Steps to reproduce:
  1. Ricevere un `assistant_update` con risposta finale e separator `---`.
  2. Finalizzare il run.
  3. Ricevere un secondo `assistant_update` tardivo sullo stesso `activityId`.
- Risultato attuale: la bubble finale poteva essere sovrascritta senza rieseguire split/cleanup coerenti.
- Risultato atteso: i response update arrivati dopo la finalizzazione devono essere ignorati; la finalize deve rimuovere il binding della response bubble.
- Causa probabile: mapping `responseMessageIds` mantenuto oltre la finalize e coda differita senza guardia sullo stato `finished`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ActionOutput.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
- Non-scope:
  - redesign del protocollo eventi review
  - introduzione di sequence number provider-side
- Moduli confinanti da verificare:
  - `CodeReviewPanelChatStateDeferralTests`
  - finalize della response bubble
- Test da aggiungere o aggiornare:
  - regressione che assicura l’immutabilità del transcript dopo `finish`
- Strategia di fix minimo:
  - scartare i `Response` update dopo `finishedReviewRunActivityIds`
  - rimuovere sempre il binding `responseMessageIds` in finalize
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests`
- Commit previsto: `fix(review-panel): ignore late response updates after finish`

## Evidenza
- la regressione nuova verifica che un update tardivo vuoto non possa cancellare o corrompere risposta finale e verdict
