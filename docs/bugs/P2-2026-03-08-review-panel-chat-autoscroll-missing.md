# P2 - Review panel chat/activity senza auto-scroll in basso

## Bug Fix Record
- Categoria: B
- Bug: nel pannello Code Review la conversazione non resta ancorata in basso durante lo stream, e la card `ACTIVITY` dentro la bubble `REVIEW RUN` non segue le nuove righe del log.
- Sintomo: durante una review live, la chat resta ferma su una posizione precedente e la sezione `ACTIVITY` mostra output vecchio finché l’utente non scrolla manualmente.
- Impatto: degrada la leggibilità del flusso live e rende facile perdere errori, tool call o avanzamento dei worker mentre la review è in corso.
- Gravità: media-alta per UX del flusso core di review.
- Steps to reproduce:
  1. Aprire il pannello Code Review.
  2. Avviare una review o una chat che produca eventi multipli in streaming.
  3. Osservare la chat e la sezione `ACTIVITY` della bubble `REVIEW RUN`.
- Risultato attuale: il contenitore chat non scende sempre all’ultimo messaggio utile e il log interno `ACTIVITY` non segue l’ultima riga.
- Risultato atteso: sia la chat sia la card `ACTIVITY` devono restare ancorate in basso durante l’arrivo di nuovi eventi.
- Causa probabile: il trigger di auto-scroll della chat era basato solo su `chatMessages.count` e `last.content`, mentre il log `ACTIVITY` aveva uno `ScrollView` interno senza alcun `scrollTo` sull’ultima riga.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatTab.swift`
  - `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/ReviewPanelChatStructuredSectionsView.swift`
  - nuovi helper/view di supporto in `App/SoloCodeApp/Sources/Panels/CodeReview/Views/Chat/`
  - test review chat in `Tests/SoloCodeAppTests/`
- Non-scope:
  - main chat agent
  - orchestration runtime
  - store dei findings o timeline
  - fix della build failure preesistente in `ToolEnabledLLMProvider+SkillExecution.swift`
- Moduli confinanti da verificare:
  - structured rendering della review chat
  - streaming/finalizzazione dei messaggi `reviewRun`
  - rendering delle sezioni log collapsible
- Test da aggiungere o aggiornare:
  - test di regressione sui fingerprint che guidano l’auto-scroll della chat
  - test di regressione sul fingerprint della sezione log `ACTIVITY`
- Strategia di fix minimo:
  - introdurre un fingerprint stabile per il messaggio finale, includendo `presentation` e stato streaming
  - scrollare la lista chat verso un bottom anchor dedicato
  - aggiungere uno scroll automatico locale alla sezione log structured
- Verifica post-fix:
  - test mirati della review chat
  - scenario manuale: avvio review live e verifica che chat e `ACTIVITY` restino in basso
  - build completa attualmente bloccata da errore fuori scope già presente nel workspace
- Commit previsto: `fix(review-chat): keep chat and activity log pinned to bottom`
