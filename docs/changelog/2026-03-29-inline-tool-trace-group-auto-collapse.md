# 2026-03-29 — Inline tool trace group auto-collapse

## Modifiche
- I gruppi inline della trace in chat (`Esplorazione effettuata`, `Terminale in background`, `Modifiche applicate`) ora partono collassati quando il gruppo e' gia' completato e si auto-collassano alla fine del task.
- Estratta la logica di auto-presentation in [`InlineToolTraceGroupAutoPresentation.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceGroupAutoPresentation.swift) e la view del gruppo in [`InlineToolTraceGroupView.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceGroupView.swift), lasciando [`InlineToolTraceViews.swift`](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/ChatView/Timeline/InlineToolTraceViews.swift) piu' piccola e confinata.
- Aggiunti test di regressione per stato iniziale, auto-collapse a completamento e riapertura manuale del gruppo completato.

## Verifiche
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/InlineToolTraceGroupAutoPresentationTests -only-testing:SoloCodeAppTests/MessageToolTraceAutoPresentationTests`
- Esito: successo, 8 test eseguiti senza failure.
