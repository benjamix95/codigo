# 2026-03-25 — Chat re-render optimization based on render log analysis

## Summary

Analisi del render log (8400 righe, 2096 EQ-MISS) ha identificato 3 cause
principali di re-render eccessivi. Fix applicato riduce drasticamente le
ri-valutazioni inutili durante lo streaming.

## Diagnosis (from render log)

```
=== EQ-MISS ChatTurnView breakdown ===
446  streamingDetailText changed      (21%)
224  streamingStatusText changed      (11%)
~1420 traceEvents.count changed       (68%)
```

Per ogni singolo tool event, 6 ChatTurnView venivano ri-valutati (tutti i
turn assistant visibili), anche se solo l'ultimo era in streaming.

423 `streamContentVersion` onChange fires, ognuno triggering la cascata.

## Root Cause

1. **toolTraceStore.events()** chiamato dentro ForEach per ogni cella.
   SwiftUI registra N dependencies separate sullo stesso ObservableObject.
   Quando `objectWillChange` fire → tutte le N celle invalidate.

2. **streamingStatusText(for:)** e **streamingDetailText(for:)** computati
   per tutti i messaggi dentro ForEach, accedendo a taskActivityStore.
   Per messaggi non-streaming, ritornano `""` / `nil` ma l'accesso
   all'ObservableObject registra comunque la dependency.

## Fixes Applied

### 1. Pre-compute trace events (`ChatPanelView+PartD_MessagesScroll.swift`)

Trace events pre-computati in un dizionario `[UUID: [ToolTraceEvent]]`
PRIMA del ForEach nella `messagesStack`. I valori vengono passati come
parametro a `chatMessageCell`, evitando l'accesso a `toolTraceStore`
dentro il body di ogni cella.

### 2. Scope streaming text to active turn only

`streamingStatusText` e `streamingDetailText` calcolati SOLO per
`isActiveStreamingAssistant` (ultimo messaggio assistant + task attivo).
Per tutti gli altri messaggi, valori stabili `""` / `nil` passati
direttamente senza accedere a `taskActivityStore`.

## Expected Impact

- **Before**: 2096 EQ-MISS per sessione, 6 re-valutazioni per tool event
- **After**: ~350 EQ-MISS (solo per il turn attivo), 1 re-valutazione per tool event
- Riduzione stimata: ~83% meno re-render inutili

## Files Changed

- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesScroll.swift`
- `docs/bugs/P0-2026-03-25-chat-excessive-rerender-all-turns.md` — NEW
- `docs/changelog/2026-03-25-chat-rerender-optimization.md` — NEW

## Risks

- Pre-computing trace events per tutti i messaggi ha costo O(N) upfront.
  Con conversazioni molto lunghe (100+ messaggi) potrebbe essere visibile,
  ma il costo e' proporzionale al numero di messaggi (non al numero di
  tool events), quindi e' trascurabile rispetto alle N*M re-render eliminate.
