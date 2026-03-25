# P2: messagesStack idle re-renders from ObservableObject cascade

## Bug Fix Record
- Categoria: C — Minore
- Bug: `messagesStack` viene ri-valutata ~24 volte all'avvio senza nessuna azione utente.
- Sintomo: Log mostra 24 `[RENDER] messagesStack` consecutivi con `msgCount=2` senza `[ONCHANGE]` triggers intermedi.
- Impatto: Spreco CPU all'avvio. Non impatta direttamente l'utente ma rallenta il tempo di startup percepito.
- Gravita: P2 — overhead all'avvio, non critico
- Causa probabile: `ChatPanelView` ha 14+ `@EnvironmentObject`. Ogni inizializzazione di uno di questi emette `objectWillChange`, che invalida `chatMessagesAreaContent` (accede a `chatStore.conversation()`), che ri-valuta `messagesStack`. 24 rebuild = ~24 ObservableObject che si inizializzano.
- Scope consentito: ChatPanelView+PartC, ChatPanelView+PartD
- Fix proposto (futuro): Estrarre il contenuto del LazyVStack in una View separata con Equatable conformance, passando solo i dati necessari come value types. Questo bloccherebbe i rebuild quando i dati non sono cambiati.
- Nota: Questo e' un problema architetturale legato al pattern di 14+ EnvironmentObject sul root view. Un fix completo richiederebbe ristrutturare la dependency injection.
