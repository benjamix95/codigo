## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la sidebar ricostruisce snapshot e render state dell'intera lista thread durante lo streaming, anche quando cambia un singolo thread attivo.
- Sintomo: con sidebar aperta e molte conversazioni, ogni burst di `chatStore.objectWillChange` innesca nuovi task debounce che rifiltrano, riordinano e ricostruiscono metriche/render state per tutti i thread.
- Impatto: lag UI e peggioramento della fluidita' durante streaming, scroll e typing; il costo cresce con il numero totale di conversazioni e con i metadati per-thread.
- Gravita': P1
- Steps to reproduce:
  1. Aprire un workspace con molte conversazioni storiche.
  2. Tenere la sidebar visibile.
  3. Avviare uno stream assistant o un task che aggiorna spesso `chatStore`.
  4. Osservare refresh continui della sidebar e degrado della reattivita'.
- Risultato attuale:
  - `SidebarView` si sottoscrive a `chatStore.objectWillChange`, `todoStore.objectWillChange` e `toolTraceStore.objectWillChange`.
  - `scheduleSidebarSnapshotRefresh()` ricostruisce l'intero snapshot dopo 120 ms.
  - `scheduleSidebarRenderStateRefresh()` ricostruisce tutti i render state dopo altri 80 ms.
  - `SidebarThreadSnapshotBuilder.build(...)` filtra/ordina tutti i thread e puo' invocare `searchThreads(...)` su tutto lo storico.
- Risultato atteso: lo streaming di un singolo thread dovrebbe aggiornare solo il delta necessario, senza ricostruire globalmente tutta la sidebar sul `MainActor`.
- Causa probabile: fan-out troppo ampio di osservazioni globali combinato con builder O(N) per snapshot e render state, entrambi eseguiti sul `MainActor`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/App/Sidebar/SidebarView.swift`
  - `App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift`
  - `App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadListSnapshot.swift`
  - `App/SoloCodeApp/Sources/Services/ChatStore/Conversations/ChatStoreConversations.swift`
- Non-scope:
  - redesign completo della sidebar
  - sostituzione di `ChatStore`
  - refactor UI non necessari al contenimento del costo
- Moduli confinanti da verificare:
  - ricerca thread AI
  - badge draft/todo/tool trace
  - selezione thread attivo
  - grouping per data e pinned threads
- Test da aggiungere o aggiornare:
  - benchmark della sidebar con 500+ conversazioni e un singolo thread in streaming
  - test che verifichi update incrementale dei soli thread sporchi
- Strategia di fix minimo:
  - ridurre gli osservatori globali
  - introdurre snapshot incrementali keyed by conversation id
  - separare la ricerca full-text dal refresh live dello stato thread
- Verifica post-fix:
  - confrontare il numero di refresh sidebar per secondo durante streaming
  - validare che pinned/grouping/badge restino coerenti
- Commit previsto:
  - docs(perf): record sidebar snapshot rebuild bottleneck

## Evidenze
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarView.swift:60-85`
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift:47-77`
- `App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadListSnapshot.swift:43-118`
- `App/SoloCodeApp/Sources/Services/ChatStore/Conversations/ChatStoreConversations.swift:185-237`
