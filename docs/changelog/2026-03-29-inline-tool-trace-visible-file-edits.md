# 2026-03-29 — Inline tool trace visible file edits

## Modifiche
- I file editati nella timeline chat non vengono piu' collassati dentro le sezioni tool: restano righe standalone visibili anche quando comprimi i gruppi con chevron.
- Introdotta una policy di grouping inline dedicata in [`ChatTurnInlineToolGroupingPolicy.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineToolGroupingPolicy.swift), lasciando collassabili solo i gruppi `exploration` e `terminal`.
- Rifinita la riga inline del file change in [`InlineToolTraceViews.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceViews.swift) per usare il titolo presentazionale del file modificato e mantenere il riepilogo `+/-`.
- Estratta una view dedicata [`ChatTurnInlineFileChangeRowView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnInlineFileChangeRowView.swift) con stile piu' vicino al mock Codex app: label azione soft, filename enfatizzato e counters colorati.

## Verifiche
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/ChatTimelineInlineToolGroupingTests -only-testing:SoloCodeAppTests/InlineToolTraceEventViewDisplayTests`
- Esito: successo, 3 test eseguiti senza failure.
