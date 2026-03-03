# Plan: Fix Plan Flow — Screening, Toggle Persistence, .solocode/plan saving

## Flusso desiderato (confermato)

```
TOGGLE ON:
  1. SCREENING (chat) → quick pre-analysis nella chat (agente sa che vuoi plan)
  2. APRE PLAN PANEL → dopo screening
  3. ANALISI PROFONDA (panel) → deep codebase exploration nel panel
  4. DOMANDE (panel) → clarification questions nel panel
  5. PLAN PRONTO (panel) → proposta con titolo auto-generato
  6. BUILD → esecuzione
  7. TODOS → sincronizzati in panel E chat

TOGGLE OFF:
  1. SCREENING (chat) → quick pre-analysis nella chat
  2. Se serve plan → AUTO-ATTIVA toggle, poi stessa cosa sopra
  3. Se non serve plan → risposta normale

TOGGLE PERSISTENCE:
  - Una volta attivato (manualmente o auto) → RIMANE ON per tutta la sessione
  - Non si disattiva durante il build (che switcha a mode .agent)
  - Non si disattiva se si aprono altri panel
```

## Plan saving:
- Ogni plan salvato come `{titolo-auto}.md` in `.solocode/plan/`
- Il titolo viene dal contenuto del plan (come Cursor)
- Il breadcrumb nel panel mostra il nome del file `.md`
- La history carica da qui
- History visibile SOLO quando l'utente apre manualmente il panel

---

## Implementazione Step-by-Step

### Step 1: Toggle persistence — NON disattivare durante build/switch mode

**File: `ChatPanelView+PartH_ComposerMode.swift`** (linea 172-184)

**Attuale:**
```swift
if mode != .plan {
    switch planFlowPhase {
    case .analyzing, .questioning, .generating, .building:
        break
    case .idle:
        break
    case .proposalReady, .readyToBuild:
        planFlowPhase = .idle
        planningState = .idle
        clearPlanStreamingState()
    }
    planToggleEnabled = false  // ← BUG: disattiva sempre
}
```

**Fix:**
```swift
if mode != .plan {
    switch planFlowPhase {
    case .analyzing, .questioning, .generating, .building:
        break
    case .idle:
        break
    case .proposalReady, .readyToBuild:
        planFlowPhase = .idle
        planningState = .idle
        clearPlanStreamingState()
    }
    // Keep toggle ON if an active plan session exists
    let hasActivePlanSession = [.analyzing, .questioning, .generating, .building, .readyToBuild]
        .contains(planFlowPhase) || activeBuildPlanConversationId != nil
    if !hasActivePlanSession {
        planToggleEnabled = false
    }
}
```

**File: `ChatPanelView+PartA_UI.swift`** (linea 212-215)

**Attuale:**
```swift
if isShowing && showPlanPanel {
    showPlanPanel = false
    planToggleEnabled = false  // ← BUG: disattiva quando debug panel si apre
}
```

**Fix:**
```swift
if isShowing && showPlanPanel {
    showPlanPanel = false
    // Do NOT disable planToggleEnabled — user may return to plan later
}
```

**File: `ChatPanelSupport+PlanFlow.swift`** — `shouldDisablePlanToggleWhenPanelCloses`

**Attuale:**
```swift
func shouldDisablePlanToggleWhenPanelCloses(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode
) -> Bool {
    guard coderMode != .plan else { return false }
    guard planningState == .idle else { return false }
    return shouldAllowPlanToggleDeactivation(phase: phase)
}
```

**Fix:** Aggiungere parametro `activeBuildPlanConversationId`:
```swift
func shouldDisablePlanToggleWhenPanelCloses(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    coderMode: CoderMode,
    hasActiveBuildSession: Bool
) -> Bool {
    guard coderMode != .plan else { return false }
    guard planningState == .idle else { return false }
    if hasActiveBuildSession { return false }
    return shouldAllowPlanToggleDeactivation(phase: phase)
}
```

---

### Step 2: Screening phase — Phase 0 prima dell'analisi

**File: `ChatPanelView+PartO_PlanPromptBuilders.swift`** — aggiungere nuovo prompt

```swift
internal func buildPhase0ScreeningPrompt(userRequest: String) -> String {
    """
    **Phase: Request Screening**

    Quickly assess whether this request needs a structured implementation plan.

    User request: \(userRequest)

    Instructions:
    1. Do NOT explore files or read code yet.
    2. Assess the request complexity in 2-3 sentences.
    3. End your response with exactly one of:
       - PLAN_NEEDED — if the request involves multiple files, architectural decisions, or non-trivial implementation
       - NO_PLAN_NEEDED — if it's a simple fix, single-file change, or straightforward task

    Be concise. This is a quick assessment, not a full analysis.
    """
}
```

**File: `ChatPanelView+PartM_MultiTurn.swift`** — aggiungere Phase 0

Prima dell'attuale Phase 1, aggiungere:

```swift
// ========================
// PHASE 0: Screening (shown in chat)
// ========================
// Don't set planFlowPhase yet — screening happens BEFORE entering plan mode
let screeningPrompt = buildPhase0ScreeningPrompt(userRequest: planUserRequest)
let screeningResult = try await flowCoordinator.runStream(
    provider: provider,
    prompt: screeningPrompt,
    context: ctx,
    attachments: attachmentsToSend,
    onText: { content in
        applyStreamingUpdate(content: content, conversationId: conversationId)
    },
    onRaw: { t, p, pid in
        handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
    },
    onError: { content in
        Task { @MainActor in
            chatStore.updateLastAssistantMessage(content: content, in: conversationId)
        }
    },
    onSignal: nil
)

let screeningText = screeningResult.trimmingCharacters(in: .whitespacesAndNewlines)
let planNeeded = screeningText.contains("PLAN_NEEDED")

// If toggle was already ON, always proceed with plan
// If toggle OFF and screening says plan needed → auto-activate
if !planToggleEnabled && planNeeded {
    await MainActor.run {
        planToggleEnabled = true
    }
}

// If no plan needed and toggle wasn't ON, just finish the chat message
if !planToggleEnabled && !planNeeded {
    chatStore.setLastAssistantStreaming(false, in: conversationId)
    clearStreamingReasoning(for: conversationId)
    return  // Exit multi-turn flow, response already in chat
}

// NOW open the plan panel (after screening, before deep analysis)
await MainActor.run {
    chatStore.updateLastAssistantMessage(
        content: screeningText,
        in: conversationId,
        persistImmediately: true
    )
    chatStore.setLastAssistantStreaming(false, in: conversationId)
    if !showPlanPanel {
        openPlanPanelForCurrentContext(
            preserveHistorySelection: false,
            source: .automaticFlow
        )
    }
}

// Continue to Phase 1 (analysis) — now in the panel...
```

**File: `ChatPanelView+PartL_PromptOptimization.swift`** (linee 133-138)

**Rimuovere** l'apertura anticipata del panel:
```swift
// RIMUOVERE QUESTO BLOCCO:
if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
    openPlanPanelForCurrentContext(
        preserveHistorySelection: false,
        source: .automaticFlow
    )
}
```

**File: `ChatPanelView+PartM_MultiTurn.swift`** (linee 71-77)

**Rimuovere** anche la seconda apertura anticipata in Phase 1.

---

### Step 3: Salvare i plan in `.solocode/plan/`

**File: `PlanHistoryStore+Mutations.swift`** — `createEntry()` scrive anche il `.md`

Dopo `entries.append(entry)` e `save()`, aggiungere:
```swift
// Also write .md file to .solocode/plan/
if let folderPath = contextFolderPath {
    let planDir = URL(fileURLWithPath: folderPath)
        .appendingPathComponent(".solocode/plan", isDirectory: true)
    try? FileManager.default.createDirectory(at: planDir, withIntermediateDirectories: true)
    let safeName = sanitizeTitle(title)
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: "_")
    let fileName = safeName.isEmpty ? "plan" : String(safeName.prefix(30))
    let fileURL = planDir.appendingPathComponent("\(fileName).md")
    try? safeMarkdown.write(to: fileURL, atomically: true, encoding: .utf8)
}
```

**File: `PlanHistoryStore+Configuration.swift`** — aggiungere costante per directory

```swift
static func solocodePlanDirectory(for workspacePath: String) -> URL {
    URL(fileURLWithPath: workspacePath)
        .appendingPathComponent(".solocode/plan", isDirectory: true)
}
```

---

### Step 4: Todos sincronizzati in chat E panel

**File: `ChatPanelView+PartM_Phase3.swift`** (linee 176-179)

**Attuale:**
```swift
chatStore.updateLastAssistantMessage(
    content: "Plan ready in Plan Panel: \(parsedSummary.title)",
    ...
)
```

**Fix:** Messaggio più ricco con todos:
```swift
let todoList = compliantOptions.first.map {
    PlanOptionsParser.extractTodosFromOptionText($0.fullText)
} ?? []
let todoMarkdown = todoList.enumerated().map { idx, t in
    "  \(idx + 1). \(t)"
}.joined(separator: "\n")
let recap = """
Plan ready: **\(parsedSummary.title)**

Steps:
\(todoMarkdown)

Open the Plan Panel to review and build.
"""
chatStore.updateLastAssistantMessage(
    content: recap,
    in: conversationId,
    persistImmediately: true
)
```

---

### Step 5: Questions skipped indicator nel PlanPhaseProgressView

**File: `PlanPanelView+Actions.swift`** (linee 60-64)

Aggiungere tracking per sapere se le questions sono state visitate.
Usare un flag `questionsWereVisited` e mostrare stato diverso:
- Se visitato → checkmark (come adesso)
- Se saltato → cerchio barrato o "Skipped"

---

## File da modificare (riepilogo)

| # | File | Modifica |
|---|------|----------|
| 1 | `ChatPanelView+PartH_ComposerMode.swift` | Toggle persistence durante mode switch |
| 2 | `ChatPanelView+PartA_UI.swift` | Non disattivare toggle quando debug panel apre |
| 3 | `ChatPanelSupport+PlanFlow.swift` | Guard build session in `shouldDisablePlanToggleWhenPanelCloses` |
| 4 | `ChatPanelView+PartO_PlanPromptBuilders.swift` | Nuovo `buildPhase0ScreeningPrompt()` |
| 5 | `ChatPanelView+PartM_MultiTurn.swift` | Aggiungere Phase 0 screening, rimuovere early open |
| 6 | `ChatPanelView+PartL_PromptOptimization.swift` | Rimuovere early panel open |
| 7 | `PlanHistoryStore+Mutations.swift` | Scrivere `.md` in `.solocode/plan/` |
| 8 | `PlanHistoryStore+Configuration.swift` | Helper per path `.solocode/plan/` |
| 9 | `ChatPanelView+PartM_Phase3.swift` | Recap ricco con todos nella chat |
| 10 | `PlanPanelView+Actions.swift` | Questions skipped indicator |

## Ordine di esecuzione

1. **Step 1** — Toggle persistence (3 file, fix critico)
2. **Step 2** — Screening phase + rimuovere early open (3 file, core)
3. **Step 3** — `.solocode/plan/` saving (2 file)
4. **Step 4** — Todos in chat (1 file)
5. **Step 5** — Questions skipped indicator (1 file)
6. Build & verify
