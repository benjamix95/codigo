## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il path `refreshMessagesSnapshot()` resta agganciato a troppi segnali live e continua a concentrare lavoro sul `MainActor` durante lo streaming.
- Sintomo: ad ogni tick di stream o cambio di store vengono ricalcolati snapshot conversazione, stato loading, swarm cards, trace events, live activity e diversi log diagnostici.
- Impatto: aumento del lavoro sul thread principale, piu' passaggi di layout/render nella chat e rischio di flicker o perdita di fluidita' su conversazioni lunghe.
- Gravita': P1
- Steps to reproduce:
  1. Aprire una conversazione lunga.
  2. Avviare uno stream con eventi testo, task activity e tool trace.
  3. Tenere visibile la timeline chat.
  4. Osservare il numero elevato di refresh del path snapshot/layout.
- Risultato attuale:
  - `refreshMessagesSnapshot()` viene chiamato da `chatStore.objectWillChange`, `pipelineIntegrationService.objectWillChange`, `streamContentVersion`, `activeTaskConversationIds`, `todoStore.objectWillChange` e `taskActivityStore.objectWillChange`.
  - il metodo legge piu' volte lo store, aggiorna snapshot ausiliari e produce logging frequente.
  - `ChatTurnView` ricostruisce segmenti interleaved e reinnesca rendering markdown/timeline nei frame successivi.
- Risultato atteso: il path di aggiornamento chat dovrebbe reagire solo ai delta strettamente necessari del turno attivo, con meno lavoro per tick e meno rebuild della view tree.
- Causa probabile: pipeline snapshot centralizzata ma ancora troppo ampia, con fan-out di eventi e attivita' accessorie rimaste sul `MainActor`.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
  - `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift`
  - `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
  - `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Parsing.swift`
- Non-scope:
  - riscrittura completa della timeline chat
  - eliminazione del bridge Swift/Rust
  - rimozione della strumentazione diagnostica non direttamente coinvolta
- Moduli confinanti da verificare:
  - auto-scroll
  - streaming footer/status text
  - tool trace inline
  - reasoning blocks
  - rendering markdown
- Test da aggiungere o aggiornare:
  - perf test sul numero di refresh per `streamContentVersion`
  - signpost o counter dedicato al path `refreshMessagesSnapshot()`
  - benchmark su timeline lunga con trace events e markdown
- Strategia di fix minimo:
  - ridurre i trigger ridondanti
  - spostare piu' lavoro fuori dal `MainActor`
  - evitare letture ripetute dello stesso store nello stesso tick
  - confinare trace/todo/swarm snapshot a delta per messaggio o conversazione attiva
- Verifica post-fix:
  - sample del main thread con chat in streaming
  - confronto di frame/layout pass prima e dopo
- Commit previsto:
  - docs(perf): record chat snapshot fanout bottleneck

## Evidenze
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift:245-385`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift:9-237`
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift:118-184`
- `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Parsing.swift:6-189`
- `.cursor/debug-7e54b6-sample.txt` mostra il main thread dominato da layout SwiftUI/AppKit e peak footprint di `490.1M`
