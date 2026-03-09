# P1 - Regressione echo asincrono review panel che porta a freeze SwiftUI

## Bug Fix Record
- Categoria: A - Critico
- Bug: il `CodeReviewPanelStore` riapplicava il mirror della chat review dal `ReviewPanelChatSessionStore` tramite `DispatchQueue.main.async`, causando un loop di invalidazione store -> session store -> store durante gli update live del pannello.
- Sintomo: warning runtime `Publishing changes from within view updates is not allowed, this will cause undefined behavior.`, spam `AttributeGraph: cycle detected ...`, CPU main thread >100%, footprint memoria in crescita e app `Solo Code` non responsiva.
- Impatto: freeze del pannello review e degrado della UI principale durante streaming chat/review; rischio alto di blocco applicativo.
- Gravità: alta lato stabilità runtime.
- Steps to reproduce:
  1. Aprire `Solo Code` e usare il pannello `Code Review` con chat/thread history attivi.
  2. Generare update live della chat review o cambiare thread mentre il pannello riflette lo stato persistito.
  3. Osservare console Xcode e responsività dell’app.
- Risultato attuale: il publish del session store schedula nuove assegnazioni `@Published` anche per snapshot identici, rientrando nel render SwiftUI e alimentando il ciclo `AttributeGraph`.
- Risultato atteso: il mirror della conversazione review deve essere differito fuori dal turno di update in corso e deve saltare assegnazioni identiche.
- Causa probabile: il `sink` del `CodeReviewPanelStore` su `ReviewPanelChatSessionStore.$conversationsByKey` rientrava durante update SwiftUI del pannello review; quando lo snapshot echo era identico o quasi identico, il panel store riapplicava comunque `chatThreads`, `activeChatThreadId`, `chatMessages`, `isChatProcessing` e `chatStartedAt`, alimentando publish reentranti e layout invalidation.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Store/CodeReviewPanelStore+ModesAndChatThreads.swift`
  - `Tests/SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests.swift`
  - documentazione bug/changelog
- Non-scope:
  - redesign del `ReviewPanelChatSessionStore`
  - refactor del pannello review
  - modifiche al runtime `VerifiedFindings`
- Moduli confinanti da verificare:
  - lifecycle chat review panel
  - session scoping del review panel
  - mirror `chatThreads` / `activeChatThreadId`
- Test da aggiungere o aggiornare:
  - regressione che verifica che uno snapshot conversazione identico non emetta un nuovo publish sul `CodeReviewPanelStore`
  - smoke sul deferral del mirror thread
  - smoke sui lifecycle test del pannello review
- Strategia di fix minimo:
  - coalescare il `sink` del session store sul tick successivo del main actor con cancellazione del task pendente
  - saltare subito gli echo identici prima di schedulare un nuovo apply
  - applicare guardie di uguaglianza sui campi `chatThreads`, `activeChatThreadId`, `chatMessages`, `isChatProcessing`, `chatStartedAt`
- Verifica post-fix:
  1. `sample` del PID `Solo Code` ha mostrato main thread in loop su `SwiftUICore` / `AttributeGraph`, non deadlock I/O.
  2. `log show` ha confermato warning `Publishing changes from within view updates is not allowed`.
  3. `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CodeReviewPanelChatStateDeferralTests -only-testing:SoloCodeAppTests/CodeReviewPanelSessionScopingTests -only-testing:SoloCodeAppTests/ReviewPanelLifecycleE2ETests`
  4. Esito: 14 test eseguiti, 0 failure.
- Commit previsto: `fix(review): stop chat session echo from re-publishing identical state`

## Note
- Questa è una ricorrenza della stessa zona fragile già documentata in `P1-2026-03-08-review-panel-chat-session-echo-publish-cycle.md`.
- Se il problema ricompare una terza volta, va aperta analisi architetturale del flusso `CodeReviewPanelStore <-> ReviewPanelChatSessionStore` invece di continuare con patch locali.
