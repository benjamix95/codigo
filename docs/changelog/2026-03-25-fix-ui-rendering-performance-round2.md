# Changelog — 2026-03-25 — UI Rendering Performance Round 2

## Contesto
Seconda passata di ottimizzazione rendering dopo il fix della rendering storm. Focus su overhead computazionale residuo durante streaming attivo.

## Fix applicati

### 1. ToolTraceStore.throttledNotify() — Ricorsione eliminata
**File**: `ToolTraceStore.swift`
- Il branch "enough time passed" chiamava ricorsivamente se stessa, generando una notifica delayed ridondante. Ora chiama `objectWillChange.send()` direttamente.

### 2. buildStreamingAttributed() — Cache per lunghezza testo
**File**: `MarkdownContentView+Views.swift`
- `AttributedString(markdown:)` veniva parsato su tutto il testo ad ogni render (~50 volte/sec). Aggiunto cache statico: se la lunghezza UTF16 non cambia, ritorna il risultato cached.

### 3. scopedTaskActivities — Eliminato UUID parse intermedio
**File**: `ChatPanelView+PartS_End.swift`
- Rimosso `canonicalConversationScope()` (trim + UUID parse + lowercased per ogni activity). Sostituito con check diretto su `activity.payload["conversation_id"]?.lowercased()`.

### 4. ChatTurnView inlineTraceEvents — Sort condizionale
**File**: `ChatTurnView.swift`
- `.filter().sorted()` O(n log n) su ogni render → check O(n) pre-sort. Se l'array è già ordinato (caso comune con NDJSON append-only), skip del sort.

## File modificati
- `App/SoloCodeApp/Sources/Tasking/ToolTraceStore.swift`
- `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Views.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartS_End.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`

## Verifica
- Build compilato con successo (`Solo Code-Debug` scheme) ✅
