# Piano: Subagent Card in Chat + Trace Filtering + Swarm Panel Performance

## Riepilogo richiesta

L'utente vuole:
1. **Subagent card in chat** — Quando l'agente invoca subagent, card espandibili appaiono **in chat** (non nel trace activity). Card stile Cursor: titolo, status in tempo reale, espandibile per vedere operato.
2. **Filtrare operazioni subagent dal trace activity** — Le attività dei subagent NON devono apparire nella "Live activity" trace. Solo le operazioni dell'agente principale.
3. **Pulsante per aprire nel swarm panel** — Click su card in chat → apre direttamente quel subagent nel swarm panel.
4. **Fix performance swarm panel** — Lagga tantissimo quando si apre.

---

## Fase 1: Filtrare operazioni subagent dal Trace Activity

**File**: `LiveActivityTimelineView.swift`, `ChatTaskStatusView.swift`

**Cosa fare**: Le attività con `swarm_id` o `group_id` con prefisso `swarm-` non devono apparire nella "Live activity" del trace.

**Modifica in `ChatTaskStatusView.swift`** (linea ~282):
```swift
// PRIMA:
let concreteActivities = taskActivityStore.activities.filter {
    TaskActivityStore.isConcreteVisibleEvent($0)
}

// DOPO:
let concreteActivities = taskActivityStore.activities.filter {
    TaskActivityStore.isConcreteVisibleEvent($0)
    && !SwarmMetadata.isSwarmEvent($0.payload)
}
```

Stessa logica per terminals, web search e grep sections — filtrare con `!SwarmMetadata.isSwarmEvent(payload)`.

Anche nel `TaskControlBar` (linea 51-52): `lastConcreteVisibleActivity` deve escludere eventi swarm per mostrare solo l'ultima operazione dell'agente principale nella barra timer.

**File da modificare**: `TaskActivityStore.swift` — aggiungere metodo `lastConcreteNonSwarmActivity()`.

---

## Fase 2: Subagent Card Inline in Chat

**Pattern di riferimento**: `PlanChatCardView` — card inline nel messaggio assistant in `chatMessageCell()` (ChatPanelView.swift:2074-2107).

**Nuovo componente**: `SubagentChatCardView.swift`

Card compatta con:
- **Header**: icona (person.2.fill), swarmId come titolo, badge status (running/completed/failed)
- **Subtitle**: `currentStepTitle` — aggiornato in tempo reale
- **Espandibile**: click per mostrare le ultime 6 operazioni (come `expandedCardEvents` in SwarmPanelView)
- **Footer**: pulsante "Open in Panel" per aprire nel swarm panel

**Data flow**: La card legge dallo `SwarmLiveCardState` che è già calcolato in `TaskActivityStore.swarmCards`.

**Dove inserire nella chat**: In `chatMessageCell()` (ChatPanelView.swift), dopo il `MessageRow`, prima del trace. Per ogni assistant message che è in streaming (l'ultimo), mostrare le card dei subagent attivi/completati.

```swift
// Dopo TodoLiveInlineCard e prima del trace
if message.id == latestAssistantMessageId {
    let cards = taskActivityStore.swarmCardStates()
    if !cards.isEmpty {
        ForEach(cards) { card in
            SubagentChatCardView(
                card: card,
                onOpenInPanel: {
                    selectedSwarmId = card.swarmId
                    showSwarmPanel = true
                }
            )
        }
    }
}
```

---

## Fase 3: Fix Performance Swarm Panel

**Cause del lag identificate**:

1. **`liveSignature` computed property** (SwarmPanelView.swift:38-42) — ricomputa una stringa da TUTTE le card ad ogni render. `onChange(of: liveSignature)` confronta stringhe grandi ogni volta che cambia qualsiasi attività. Viene chiamato sia nel body (linea 80) che in `overviewList` (linea 265).

2. **`sortedCards` computed property** (linea 30-31) — chiama `swarmCardStates()` che crea copie dell'intero dizionario, poi `sorted()` riordina. Ricalcolato ad ogni render del body e di ogni sotto-view che lo referenzia.

3. **`recentOverviewActivities`** (linea 44-45) — `concreteRecentActivities(limit: 12)` filtra e copia array ad ogni render.

4. **`overviewCard` non usa LazyVStack** — ForEach con card dentro `LazyVStack` va bene, ma il contenuto dei card (eventi espansi) viene renderizzato tutto.

5. **Non-lazy `ForEach` nel detailView** (linea 552) — `ForEach(events)` con potenzialmente 80 eventi tutti renderizzati senza lazy.

**Fix**:

A. **Cachare `sortedCards`**: Usare `@State` o memo con invalidation basata su `swarmEventsReceivedCount` invece di ricomputare ad ogni render.

B. **Semplificare `liveSignature`**: Sostituire con `onChange(of: taskActivityStore.swarmEventsReceivedCount)` — è un Int, confronto O(1).

C. **Lazy nel detailView**: Wrappare ForEach eventi in `LazyVStack`.

D. **Ridurre re-render**: Estrarre overview card in componente separato con `@ObservedObject` isolato, così non tutti i card si re-renderizzano quando uno cambia.

---

## Fase 4: Rinominare "Swarm" → "Subagent" nel panel

**File**: `SwarmPanelView.swift`
- Linea 101: `"Swarm"` → `"Subagent"`
- Linea 227: `"No swarm activity"` → `"No subagent activity"`
- Linea 230: `"Swarm agents will appear here"` → `"Subagents will appear here"`
- Linea 317: `"Swarm Activity"` → `"Subagent Activity"`
- Linea 515: `"All Swarms"` → `"All Subagents"`

---

## File da creare

| File | Descrizione |
|------|-------------|
| `Sources/CoderIDE/SubagentChatCardView.swift` | Card inline in chat per subagent |

## File da modificare

| File | Modifica |
|------|----------|
| `ChatTaskStatusView.swift` | Filtrare eventi swarm dal trace |
| `ChatPanelView.swift` | Inserire SubagentChatCardView nella chat |
| `SwarmPanelView.swift` | Fix performance + rename labels |
| `TaskActivityStore.swift` | Aggiungere `lastConcreteNonSwarmActivity()` |
| `ChatTaskStatusView.swift` (TaskControlBar) | Usare attività non-swarm nella barra timer |

## Ordine di esecuzione

1. Fase 1 — Filtrare subagent dal trace (rapido, impatto immediato)
2. Fase 2 — Creare SubagentChatCardView e inserire in chat
3. Fase 3 — Fix performance swarm panel
4. Fase 4 — Rename labels
5. Build + verify
