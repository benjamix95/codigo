# Piano: Fix Plan Mode Flow

## Problema
Il flusso del plan mode ha 8 problemi interconnessi che rompono l'esperienza utente.

---

## Fase A: Prompt - 1 piano definitivo (non 2-4 opzioni)

### A1. `ChatPanelView.swift` linee 5593-5638 — `planningInstructions` inline
**Cambiare:**
```
## PHASE 3: PLAN PROPOSAL (ONLY after Phases 1+2 resolved)
Propose 2-4 concrete options:
## Option 1: Title
```
**In:**
```
## PHASE 3: DEFINITIVE PLAN (ONLY after Phases 1+2 resolved)
Generate ONE definitive implementation plan (the best approach):
## Plan: Title
Description, rationale, trade-offs.
## Todo
- [ ] Step 1
- [ ] Step 2
```
Rimuovere riferimenti a "2-4 options", "## Option 2", ecc.

### A2. `ChatPanelView.swift` linea 5567 — post-clarification template
**Cambiare:** `"proceed to propose 2-4 options with ## Option and ## Todo sections"`
**In:** `"proceed to generate ONE definitive plan with ## Plan: Title and ## Todo sections"`

### A3. `ChatPanelView.swift` linee 5803-5856 — `buildPhase3GenerationPrompt`
**Cambiare tutto il prompt:** da "Generate 2-4 concrete implementation options" a "Generate ONE definitive implementation plan". Formato atteso:
```
## Plan: Title
Description...
## Todo
- [ ] Step 1
...
```
Rimuovere `## Option 1`, `## Option 2`, pros/cons per opzione.

### A4. `ChatPanelView.swift` linee 5859-5900 — `buildPhase3TodoComplianceRepairPrompt`
**Cambiare:** "Output 2-4 options using headers like `## Option 1:`"
**In:** "Output ONE plan using header `## Plan: Title`"

### A5. `PlanOptionsParser.swift` — riconoscere `## Plan:` come header
Nel pattern regex `optionHeaderPattern` (circa linea 84), aggiungere `Plan` come keyword:
```swift
#"(?i)^\s*(?:#{1,3}\s*)?(?:Option|Approach|Plan)\s+(?:\d+|[A-Z])?\s*[:\-\u{2013}\u{2014}]"#
```
E nel `parseStrict`, accettare `options.count == 1` come risultato valido (attualmente richiede >= 2 per il fast path).

### A6. `PlanPanelView.swift` linea 149 — auto-select opzione singola
Quando `options.count == 1`, auto-selezionare e saltare il chooser UI:
```swift
if case .awaitingChoice(_, let options) = planningState {
    if options.count == 1 {
        // Auto-select the single plan
        onSelectOption(options[0], planProviderId)
    } else {
        PlanOptionsView(...)
    }
}
```

---

## Fase B: Chat — non sovrascrivere, non mostrare contenuto raw

### B1. Fase 1 completata — preservare analisi in chat
`ChatPanelView.swift` linee 4884-4892:
**Attualmente:** sovrascrive il messaggio con "Analysis complete. Generating questions..."
**Fix:** Tenere il fullText dell'analisi nel messaggio corrente. Aggiungere un NUOVO messaggio assistant per la transizione:
```swift
// Preserve analysis in current message
chatStore.updateLastAssistantMessage(
    content: analysisResult.fullText, in: conversationId, persistImmediately: true
)
chatStore.setLastAssistantStreaming(false, in: conversationId)
// New transition message
chatStore.addMessage(
    ChatMessage(id: UUID(), role: .assistant, content: "Analysis complete. Preparing clarification..."),
    to: conversationId
)
```

### B2. Fase 2 — domande SOLO nel panel, non in chat
`ChatPanelView.swift` linee 4920-4938 — Phase 2 `onText` callback:
**Attualmente:** `applyStreamingUpdate(content: content, conversationId: conversationId)` mostra domande in chat
**Fix:** NON streamare alla chat. Solo aggiornare `planStreamingContent`. Mostrare messaggio statico:
```swift
onText: { [self] content in
    planStreamingContent = content
    // Static status in chat — questions only in panel
},
```
Prima di avviare lo stream Phase 2, impostare il messaggio chat a "Generating clarification questions..." e non aggiornarlo durante lo streaming.

Anche a linea 4952: quando le domande sono pronte, NON scrivere `questionText` in chat. Scrivere:
```swift
chatStore.updateLastAssistantMessage(
    content: "Questions ready — answer in the plan panel.",
    in: conversationId, persistImmediately: true
)
```

### B3. Fase 2 "no questions needed" — non sovrascrivere
`ChatPanelView.swift` linee 4970-4982:
**Attualmente:** sovrascrive con "No questions needed. Generating plan..."
**Fix:** Aggiungere nuovo messaggio invece di sovrascrivere:
```swift
chatStore.addMessage(
    ChatMessage(id: UUID(), role: .assistant, content: "No questions needed. Generating plan..."),
    to: conversationId
)
```

### B4. Fase 3 streaming — nascondere contenuto raw dalla chat
`ChatPanelView.swift` linee 5027-5033 — Phase 3 `onText`:
**Attualmente:** `applyStreamingUpdate(content: content, conversationId: conversationId)` mostra raw markdown con `- [ ]` in chat
**Fix:** Come Phase 2, streamare SOLO al plan panel:
```swift
onText: { [self] content in
    planStreamingContent = content
    // Plan content only in panel, static status in chat
},
```
Impostare il messaggio chat a "Generating definitive plan..." prima dello stream.

### B5. Fase 3 completata — non sovrascrivere
`ChatPanelView.swift` linee 5111-5122:
**Attualmente:** prima scrive `full` poi sovrascrive con "Plan ready: title"
**Fix:** Il messaggio corrente rimane "Generating definitive plan..." (status). Aggiungere NUOVO messaggio con summary + mermaid:
```swift
let mermaidBlocks = PlanOptionsParser.extractMermaidBlocksForDisplay(full)
let mermaidSection = mermaidBlocks.first.map { "\n\n```mermaid\n\($0)\n```" } ?? ""
let summaryContent = "Plan ready: \(parsedSummary.title)\(mermaidSection)"
chatStore.addMessage(
    ChatMessage(id: UUID(), role: .assistant, content: summaryContent),
    to: conversationId
)
```

### B6. Strippare false todo checkboxes durante building
`ChatPanelView.swift` — aggiungere helper:
```swift
private func stripPlanCheckboxes(_ content: String) -> String {
    content.replacingOccurrences(
        of: #"(?m)^(\s*[-*]\s*)\[\s*[xX ]?\s*\]\s*"#,
        with: "$1",
        options: .regularExpression
    )
}
```
In `applyStreamingUpdate` (linea 6252), quando `planFlowPhase == .building`:
```swift
let sanitized = planFlowPhase == .building ? stripPlanCheckboxes(content) : content
chatStore.updateLastAssistantMessage(content: sanitized, in: conversationId, ...)
```

---

## Fase C: Mermaid diagrams

### C1. Fase 1 analysis prompt — richiedere mermaid
`ChatPanelView.swift` linea 5709, `buildPhase1AnalysisPrompt`:
Aggiungere istruzione:
```
8. Include a ```mermaid diagram showing the architecture, component relationships, or data flow relevant to this request.
```

### C2. Fase 3 generation prompt — richiedere mermaid
Già presente in `planningInstructions` (linea 5629-5634). Verificare che il prompt Phase 3 lo includa. Aggiungere esplicitamente:
```
- Include a ```mermaid diagram showing the implementation plan dependencies and flow.
```

### C3. Plan panel — già funziona
`PlanPanelView.swift` linee 168-173 già estrae e mostra mermaid dal contenuto del piano. Nessuna modifica necessaria.

---

## Fase D: Walkthrough card + recap chat

### D1. Walkthrough dopo build completato
`ChatPanelView.swift` linee 4443-4474 — dopo il build stream completa con successo:
Aggiungere prima di `activeBuildPlanConversationId = nil` (linea 4473):
```swift
// Generate walkthrough
if let planConvId = activeBuildPlanConversationId {
    let canonicalTodos = todoStore.todos.filter(\.isPlanCanonical)
    let walkthroughMd = buildWalkthroughMarkdown(
        canonicalTodos: canonicalTodos,
        planBoard: chatStore.planBoard(for: planConvId)
    )
    chatStore.setWalkthrough(walkthroughMd, for: planConvId)
}
```

Aggiungere helper:
```swift
private func buildWalkthroughMarkdown(
    canonicalTodos: [TodoItem],
    planBoard: PlanBoard?
) -> String {
    var lines: [String] = ["## Build Complete", ""]
    if let goal = planBoard?.goal, !goal.isEmpty {
        lines.append("**Objective:** \(goal)")
        lines.append("")
    }
    lines.append("### Completed Steps")
    for todo in canonicalTodos {
        let icon = todo.status == .done ? "x" : " "
        lines.append("- [\(icon)] \(todo.title)")
        if !todo.linkedFiles.isEmpty {
            lines.append("  Files: \(todo.linkedFiles.joined(separator: ", "))")
        }
    }
    return lines.joined(separator: "\n")
}
```

### D2. Recap in chat dopo build
Nello stesso blocco `await MainActor.run` (linea 4467), aggiungere recap:
```swift
let canonicalTodos = todoStore.todos.filter(\.isPlanCanonical)
let doneCount = canonicalTodos.filter { $0.status == .done }.count
let totalCount = canonicalTodos.count
let goalText = chatStore.planBoard(for: planConversationId)?.goal ?? "Plan"
let recap = doneCount == totalCount
    ? "Build complete. All \(totalCount) steps done: \(goalText)"
    : "Build finished. \(doneCount)/\(totalCount) steps completed: \(goalText)"
chatStore.addMessage(
    ChatMessage(id: UUID(), role: .assistant, content: recap),
    to: agentConvId
)
```

---

## Fase E: Sync bidirezionale

### E1. Verificare wiring TodoStore → PlanBoard
`TodoStore.onCanonicalTodoStatusChange` callback deve chiamare `chatStore.syncPlanStepsFromCanonicalTodos`. Verificare in ChatPanelView.swift dove viene assegnato e che funzioni correttamente.

### E2. PlanBoard → TodoStore (cross-sync)
Esiste già in `handleRawStreamEvent` linee 2715-2752 (`planStepUpdate` → `todoStore.upsertCanonicalOnlyFromAgent`). Verificare che funzioni.

---

## Ordine di implementazione
1. **A1-A5**: Prompt + parser per 1 piano (basso rischio)
2. **B1-B5**: Chat preservation + nascondere raw content (rischio medio)
3. **B6**: Strip checkboxes durante building (basso rischio)
4. **A6**: Auto-select piano singolo nel panel (basso rischio)
5. **C1-C2**: Mermaid nei prompt (basso rischio)
6. **D1-D2**: Walkthrough + recap (basso rischio, additivo)
7. **E1-E2**: Verifica sync (solo verifica)

## File coinvolti
- `Sources/CoderIDE/ChatPanelView.swift` — modifiche principali (prompt, flow, streaming, walkthrough)
- `Sources/CoderIDE/PlanOptionsParser.swift` — riconoscere `## Plan:` header
- `Sources/CoderIDE/PlanPanelView.swift` — auto-select piano singolo
- `CoderEngine/Sources/CoderEngine/SystemPrompts/PromptPlanningPolicy.swift` — opzionale, allineare policy
