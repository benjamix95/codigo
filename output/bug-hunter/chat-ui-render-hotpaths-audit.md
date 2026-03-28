# Chat UI render hotpaths audit

Data: 2026-03-29
Scope: layer chat/UI, snapshot/render path, trace/todo/activity fan-out

## Summary

Il layer chat ha gia introdotto snapshot e throttling, ma restano alcuni punti che continuano a scalare male quando la conversazione cresce o quando il thread riceve update frequenti.
I colli principali sono:

1. fan-out troppo ampio nel root `ChatPanelView`
2. letture dirette da store dentro il rendering dell'header e delle celle messaggio
3. ricostruzione completa della timeline assistente ad ogni invalidazione
4. refresh snapshot che resta costoso e duplicato su trace e stato live

## Findings per priorita

### [HIGH] `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView.swift:9-126`

Funzioni / aree:
- `ChatPanelView.body`
- `ChatPanelView.rootLayout`
- `ChatPanelView.messagesArea`

Motivo del collo di bottiglia:
- il root view porta 14 `@EnvironmentObject`, 3 `@StateObject`, molti `@State` e vari `Binding`
- ogni cambiamento su uno di questi oggetti puo rientrare nel body root e ri-evaluare una gerarchia molto ampia
- il file contiene ancora stato di supporto molto diverso nello stesso tree: chat, composer, sidebar, swarm, plan, debug, browser
- anche se alcuni dati sono gia snapshotizzati, il root resta il punto di fan-out iniziale che attiva il resto della pipeline

Impatto osservabile:
- render inutile su cambi di stato non legati ai messaggi
- costo di layout e diff SwiftUI su aree non toccate dal cambiamento

### [HIGH] `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift:28-85, 121-180, 232-295`

Funzioni / aree:
- `shouldHideBuildKickoffMessage(_:in:)`
- `chatTitlebarDisplayTitle`
- `rewindButton`
- `messagesArea`

Motivo del collo di bottiglia:
- `shouldHideBuildKickoffMessage` viene valutata nel path di rendering e fa piu lookup di store per ogni messaggio assistente
- usa `toolTraceStore.hasTrace`, `chatStore.isTaskActive`, `chatStore.conversation(for:)` e `todoStore.displayTodosForChat(...)` nella stessa decisione
- `chatTitlebarDisplayTitle` legge `chatStore.conversation(for:)` ad ogni rebuild dell header
- `rewindButton` legge `chatStore.canRewind(...)` sia per stile sia per disabled state
- `messagesArea` ascolta `chatStore.objectWillChange` e `pipelineIntegrationService.snapshotDidChangePublisher`, quindi anche mutazioni non direttamente legate alla lista messaggi possono risvegliare tutta la sezione

Impatto osservabile:
- invalidazioni ripetute dell header e del gate di visibilita kickoff
- churn inutile quando cambiano stati correlati ma non visibili

### [HIGH] `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessageCell.swift:82-355`

Funzioni / aree:
- `chatMessageCell(message:index:lastMsg:todoCardAssistantMessageId:conversationId:precomputedTraceEvents:)`
- `resolveChatStreamingFooterResolution(...)`

Motivo del collo di bottiglia:
- ogni cella assistant ricalcola `todoStore.displayPlanScopedTodos(...)` anche quando il todo card non viene mostrato
- per le card di piano fa lookup su `planHistoryStore.findEntry(...)` e poi genera piu closure di azione
- costruisce `displayMessage`, redaction e controlli debug nel corpo della cella
- la parte assistant usa `ChatTodoMarkdownInspection.combinedVisibleTextualPayload(...)` e log NDJSON in render path
- in thread lunghi questo diventa un costo O(n) per ogni invalidazione della lista, moltiplicato per il numero di celle visibili

Impatto osservabile:
- lavoro ripetuto per ogni messaggio visibile
- maggiore pressione su main thread durante streaming e quando lo store emette update frequenti

### [HIGH] `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift:122-170, 172-236`

Funzioni / aree:
- `inlineTraceEvents`
- `interleavedSegments`
- `body`

File correlato:
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift:8-77, 132-255`

Motivo del collo di bottiglia:
- `inlineTraceEvents` filtra e puo ordinare le trace ad ogni valutazione della view
- `interleavedSegments` ricostruisce tutta la timeline del turno ad ogni invalidazione
- `ChatTurnTimelineInterleaver.segments(...)` fa collapse, sort e sequence resolution su blocchi, trace e subagent cards ogni volta
- la view e usata per ogni assistente, quindi l'ammontare di lavoro cresce con il numero di messaggi e con la densita delle trace

Impatto osservabile:
- ricostruzione ripetuta della timeline anche quando cambia solo uno stato esterno del parent
- costo CPU elevato nei turni lunghi con molte trace/tool event

### [MEDIUM] `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageSnapshotRefresh.swift:9-185, 191-281`

Funzioni / aree:
- `refreshMessagesSnapshot()`
- `chatMessageTimelinePayloadCharSum(_:)`
- `refreshTraceEventsSnapshot(fresh:)` in `ChatPanelView+PartC_MessageSnapshotTraces.swift:6-23`

Motivo del collo di bottiglia:
- il refresh viene chiamato su ogni `streamContentVersion` e su cambi del conteggio messaggi
- confronta piu campi dell ultimo messaggio e fa piu letture ripetute di `chatStore.conversation(for:)`
- `refreshTraceEventsSnapshot` itera su tutti i messaggi assistant e chiama `toolTraceStore.events(...)` per ciascuno
- il path e throttled, ma resta un lavoro completo sulla conversazione e sulla trace map

Impatto osservabile:
- costo che cresce con lunghezza conversazione e numero di assistant turn
- doppio lavoro tra snapshot conversazione, snapshot trace e stato live

### [MEDIUM] `App/SoloCodeApp/Sources/Swarm/Views/SubagentChatView.swift:11-42`

Funzioni / aree:
- `segments`
- `body`
- `scrollToBottom(_:)`

Motivo del collo di bottiglia:
- `SubagentChatSegmentBuilder.build(from:)` viene richiamato ad ogni render
- tre `onChange` separati su `transcript.count`, `liveText.count` e `recentEvents.count` possono causare scroll ripetuti
- il componente e leggibile, ma su update live molto frequenti resta un hotpath secondario quando il pannello swarm e aperto

Impatto osservabile:
- scrolling ripetuto e rebuild della lista segmenti durante streaming del subagent

### [LOW] `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow+Content.swift:74-323`

Funzioni / aree:
- `messageContent()`
- `messageActionsRow()`
- `copyMessageToClipboard()`
- `userAttachmentsRow(attachments:)`

Motivo del collo di bottiglia:
- il rendering della cella messaggio fa branching consistente su user/assistant, reasoning, attachments e streaming
- usa `Task.sleep` e `DispatchQueue.main.asyncAfter` per hover/copy feedback su ogni cella
- i task sono cancellati correttamente, quindi il rischio e contenuto, ma e comunque un costo locale presente in ogni riga visibile

Impatto osservabile:
- piccoli task UI per cella
- costo cumulativo quando molte righe sono visibili

## Note operative

- La parte piu costosa sembra essere la combinazione tra `ChatTurnView` e le letture dirette dagli store nell header/celle del thread.
- Il refresh snapshot ha gia throttling e guard rail, ma resta il secondo asse di costo principale per i thread lunghi.
- Non sono stati eseguiti fix applicativi in questo giro: questo e un audit di hotpath e non una patch.

