# Changelog

## 2026-03-29

### Fix
- corretto il merge della timeline streaming perché, prima del fallback sintetico, recuperi il `ChatTurnState` dal messaggio persistito dello stesso assistant message quando questo è più ricco dello snapshot base
- estratto un restore puro del `ChatTurnState` da `ChatMessage`, riusato sia dall'adapter pipeline sia dall'hydration della cache timeline
- evitato il caso in cui una snapshot chat monolitica rimpiazzi la timeline interleavata già disponibile nello store persistito

### Test
- aggiunti test dedicati in `/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/ChatStreamingTimelineTurnResolverTests.swift`
- coperti i casi:
  - restore `text/tool/text` da messaggio persistito
  - preferenza del persisted turn rispetto al fallback sintetico
  - preferenza della cache per assistant message rispetto al turn attivo di un altro assistant
  - conservazione del fallback sintetico quando nessun turn reale esiste

### Evidenze
- i log locali mostravano `merge_uses_synthetic_turn_from_tool_trace_events` con `reason=no_pipeline_turn` proprio sui messaggi che poi apparivano monolitici
- in quei casi il fallback sintetico ricostruiva i marker tool, ma non poteva risuddividere un testo già collassato in un solo `primaryText`
