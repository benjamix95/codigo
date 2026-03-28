# Changelog — 2026-03-28

## Fix Chat: il composer todo non dipende più da una soglia di 400 caratteri per riconoscere i documenti piano strutturati

### Cosa è cambiato
- `ChatTodoMarkdownInspection` ora riconosce i documenti piano/todo strutturati tramite heading `## Plan` / `## Todo`, checklist GitHub-style, liste numerate e diagrammi Mermaid, senza richiedere un payload lungo.
- `ChatPanelView+PlanArtifactVisibility.hasStructuredPlanMarkdownDocumentInThread` usa il nuovo helper puro e non scarta più i documenti brevi ma già strutturati.
- Sono stati aggiunti due test di regressione: uno per un piano breve ma strutturato, uno per una risposta con bullet list semplice che non deve attivare la soppressione.

### Perché
- La soglia minima di 400 caratteri poteva lasciare visibile l’overlay composer anche quando la chat conteneva già un documento todo/plan breve, producendo duplicazione percepita come “todo ancora molto male”.

### File toccati
- `App/SoloCodeApp/Sources/ChatView/Timeline/Support/ChatTodoMarkdownInspection.swift`
- `App/SoloCodeApp/Sources/Services/ChatPlan/Runtime/ChatPanelView+PlanArtifactVisibility.swift`
- `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
