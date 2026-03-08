# P1 - Publish di store SwiftUI durante il ciclo di update view in task activity, usage e review panel

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: diversi store osservati da SwiftUI pubblicano cambiamenti mentre la UI sta ancora eseguendo `body`, `onAppear` o callback di update strettamente collegate al render.
- Sintomo: warning runtime `Publishing changes from within view updates is not allowed, this will cause undefined behavior.` con riferimenti a `TaskActivityStore`, `ProviderUsageStore`, `AccountUsageDashboardStore` e `CodeReviewPanelStore+ActionOutput`.
- Impatto: comportamento UI non deterministico, rischio di refresh reentranti, stato live swarm/usage instabile e pannello review che aggiorna store secondari nel turno sbagliato.
- Gravità: alta lato affidabilità runtime UI, media lato perdita funzionale diretta
- Steps to reproduce:
  1. Aprire la chat o il pannello swarm con task attivo e lasciare arrivare eventi live.
  2. Aprire footer usage o menu bar usage mentre parte un refresh provider/dashboard.
  3. Avviare una review con stream eventi raw nel pannello Code Review.
  4. Osservare la console runtime di Xcode.
- Risultato attuale: alcune query usate dal `body` mutano cache `@Published`; alcuni refresh async e ingest review pubblicano stato nello stesso turno di update SwiftUI.
- Risultato atteso: le query lette dal `body` devono essere side-effect free; i refresh e gli ingest avviati dal lifecycle UI devono pubblicare solo nel tick successivo del main actor.
- Causa probabile: `TaskActivityStore.swarmCardStates(for:)` rinfresca cache durante la lettura; `AccountUsageDashboardStore.refresh()` e `ProviderUsageStore.fetch*()` impostano subito stato osservato; `CodeReviewPanelStore+ActionOutput.swift` inoltra eventi al `TaskActivityStore` nello stesso turno di update del pannello.
- Scope consentito: `TaskActivityStore+Swarm.swift`, `TaskActivityStore+Query.swift`, `AccountUsageDashboardStore.swift`, `ProviderUsageStore.swift`, `CodeReviewPanelStore+ActionOutput.swift`, `TaskActivityStoreSwarmCardsTests.swift`, docs bug/changelog.
- Non-scope: refactor architetturale dei pannelli, redesign dei flow review/swarm, cleanup di store non segnalati.
- Moduli confinanti da verificare: rendering swarm cards in chat/pannello, footer usage, menu bar usage, ingest eventi review.
- Test da aggiungere o aggiornare: regressione che verifica che la lettura di `swarmCardStates()` non emetta `objectWillChange`.
- Strategia di fix minimo: rendere pura la lettura delle swarm cards, differire di un tick i refresh async osservati dalla UI e sganciare l'ingest review dal turno di render corrente.
- Verifica post-fix:
  1. Eseguire `TaskActivityStoreSwarmCardsTests`.
  2. Eseguire una build/test del target app per verificare che i file modificati compilino.
  3. Rieseguire i flussi usage/review e verificare assenza dei warning in console.
- Commit previsto: `fix(swiftui): defer store publishes outside view updates`
