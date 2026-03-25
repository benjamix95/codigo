# P0: Chat UI re-renders all message turns on every streaming event

## Bug Fix Record
- Categoria: A — Critico
- Bug: Durante lo streaming, TUTTI i ChatTurnView visibili vengono ri-renderizzati ad ogni singolo tool trace event e cambio di stato, invece del solo messaggio attivo.
- Sintomo: 2096 EQ-MISS in una singola sessione. 6 ChatTurnView invalidati per ogni tool event (68%), ogni cambio di streamingDetailText (21%), ogni cambio di streamingStatusText (11%).
- Impatto: Main thread saturo, UI laggy durante streaming, potenziale black screen.
- Gravita: P0 — impatta performance core dell'app
- Steps to reproduce: Avviare una conversazione con tool use. Osservare i log `[EQ-MISS]` — 6 ri-valutazioni per ogni singolo tool event.
- Risultato attuale: 2096 EQ-MISS, ~1420 da traceEvents.count, ~670 da streaming text
- Risultato atteso: Solo 1 ChatTurnView ri-renderizzato per evento (l'ultimo assistant in streaming)
- Causa probabile:
  1. `toolTraceStore.events()` chiamato dentro ForEach per OGNI cella → registra N dependencies SwiftUI separate sullo stesso ObservableObject → quando `objectWillChange` fire, tutte le N celle vengono invalidate.
  2. `streamingStatusText(for:)` e `streamingDetailText(for:)` calcolati per TUTTI i messaggi dentro ForEach, accedendo a `taskActivityStore` → stessa amplificazione delle dependencies.
- Scope consentito: `ChatPanelView+PartD_MessagesScroll.swift`
- Non-scope: ToolTraceStore internals, TaskActivityStore internals
- Moduli confinanti da verificare: ChatTurnView Equatable, scroll auto behavior
- Test da aggiungere: Performance test che misura re-render count durante streaming
- Strategia di fix minimo:
  1. Pre-computare `traceEvents` per tutti i messaggi PRIMA del ForEach in un dizionario. I valori pre-computati vengono passati come parametro, evitando accesso all'ObservableObject dentro il body di ogni cella.
  2. Computare `streamingStatusText`/`streamingDetailText` SOLO per l'ultimo assistant in streaming. Per tutti gli altri messaggi, passare valori stabili (`""`, `nil`) senza accedere a `taskActivityStore`.
- Verifica post-fix: Con lo stesso scenario, le EQ-MISS dovrebbero scendere drasticamente (solo per l'ultimo turn attivo).
- Commit previsto: perf(chat): eliminate N×M re-renders by pre-computing trace events and scoping streaming text
