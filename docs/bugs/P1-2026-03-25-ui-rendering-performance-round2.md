# P1 — UI Rendering Performance — Second Pass

**Data**: 2026-03-25
**Categoria**: B — Importante
**Contesto**: Analisi di follow-up dopo il fix della rendering storm (P0-2026-03-25). Focus su overhead computazionale residuo durante lo streaming.
**Stato**: ✅ FIX APPLICATI

---

## Bug Trovati e Fixati

### BUG 1 — ToolTraceStore.throttledNotify() ricorsione mascherata (P1) ✅
- **File**: `ToolTraceStore.swift:113-127`
- **Problema**: La funzione `throttledNotify()` nel branch "enough time passed" chiamava ricorsivamente se stessa invece di `objectWillChange.send()`. Questo causava: (1) uno stack frame sprecato, (2) una notifica delayed ridondante schedulata oltre a quella immediata.
- **Fix**: Il branch immediato ora chiama `objectWillChange.send()` direttamente e cancella eventuali task pending.

### BUG 2 — buildStreamingAttributed() re-parse ad ogni render (P1) ✅
- **File**: `MarkdownContentView+Views.swift:38-65`
- **Problema**: Durante lo streaming, `AttributedString(markdown: text)` veniva parsato su tutto il contenuto ad ogni render (~20ms). Questo include il parser markdown di sistema + l'iterazione di tutti i runs per applicare stili inline code.
- **Fix**: Aggiunto cache statico basato su `text.utf16.count`. Durante lo streaming il testo cresce in append-only — se la lunghezza non cambia, il risultato cached viene riutilizzato (skip del parse completamente).

### BUG 3 — scopedTaskActivities O(n) con UUID parse su ogni activity (P1) ✅
- **File**: `ChatPanelView+PartS_End.swift:114-120`
- **Problema**: Per ogni activity nel filtro, `canonicalConversationScope()` faceva: (1) trim whitespace, (2) UUID parse, (3) lowercased(). Con 200+ activities durante un task complesso, questo è significativo.
- **Fix**: Inlined il check direttamente sul payload (`activity.payload["conversation_id"]?.lowercased()`), eliminando il parsing UUID intermedio.

### BUG 4 — ChatTurnView inlineTraceEvents sort O(n log n) su dati già ordinati (P1) ✅
- **File**: `ChatTurnView.swift:35-42`
- **Problema**: `inlineTraceEvents` faceva `.filter().sorted()` ad ogni render. Ma i traceEvents da `ToolTraceStore` sono già in ordine di inserimento (NDJSON append-only) e `.filter()` preserva l'ordine relativo.
- **Fix**: Aggiunto check O(n) pre-sort che verifica se l'array è già ordinato (caso comune). Il sort O(n log n) viene eseguito solo se necessario.

---

## Bug Identificati ma Non Fixati (richiedono refactor strutturale)

### ChatTurnView non Equatable (P2 — Backlog)
- **File**: `ChatTurnView.swift:4`
- SwiftUI non può fare diff-skip senza Equatable. Ma `ChatTurnView` ha 15 parametri con closure non-Equatable (`onFileClicked`, `onReviewChanges`, etc.). Servirerebbe un refactor architetturale con action enum.

### 15 EnvironmentObject su ChatPanelView (P2 — Backlog)
- **File**: `ChatPanelView.swift:9-24`
- Ogni `@EnvironmentObject` è un potenziale invalidation source. Ridurre richiede un refactor dell'intera gerarchia view con ViewStore/Selector pattern.

### ForEach id: \.self su String arrays (P3 — Cosmetico)
- **File**: `ArtifactCardView.swift:64`
- Non impattante durante lo streaming, solo durante rebuild di card artifacts statiche.

---

## File Modificati
- `App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift`
- `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Views.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartS_End.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
