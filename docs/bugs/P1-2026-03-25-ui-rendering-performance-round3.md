# P1 — UI Rendering Performance — Third Pass

**Data**: 2026-03-25
**Categoria**: B — Importante
**Contesto**: Terza passata dopo round 1 (rendering storm) e round 2 (throttle/cache). Focus su @Published notification frequency e hot-path string allocations.
**Stato**: ✅ FIX APPLICATI

---

## Bug Trovati e Fixati

### BUG 1 — ChatStore fallbackUpdateAssistantContent double mutation (P0) ✅
- **File**: `ChatStore+RustBridge.swift:40-41`
- **Problema**: Due assegnazioni separate a `conversations[i].messages[j].content` e `.primaryTextSnapshot` triggeravano DUE notifiche `@Published` separate → due rebuilds della view hierarchy.
- **Fix**: Coalescenza in una singola mutazione: estrae il messaggio in var locale, modifica entrambi i campi, riassegna una volta sola.

### BUG 2 — scopedTaskActivities .lowercased() per-activity allocation (P1) ✅
- **File**: `ChatPanelView+PartS_End.swift:121-125`
- **Problema**: `raw.lowercased()` allocava una nuova String per ogni activity nel filtro. Con 200+ activities, significative allocazioni durante ogni render.
- **Fix**: Sostituito con `raw.caseInsensitiveCompare(expected)` — zero allocazioni, confronto diretto.

### BUG 3 — PanelResizeHandle setter fires at 60 FPS (P2) ✅
- **File**: `DesignSystem+ViewHelpers.swift:156`
- **Problema**: `panelWidth = newWidth` veniva chiamato ad ogni evento drag (60+ volte/sec). Il setter scrive a `@AppStorage` (UserDefaults sync) e trigga view invalidation.
- **Fix**: Threshold di 2pt minimo prima dell'update. Riduce gli aggiornamenti a ~30/sec — visivamente identico.

---

## Bug Identificati ma Non Fixati (architetturali)

### ChatStore @Published senza throttle globale (P1 — Backlog)
- 6 `@Published` properties senza throttle. Un refactor a `objectWillChange` manuale sarebbe troppo invasivo. Il fix di coalescenza per `fallbackUpdateAssistantContent` mitiga il caso più frequente (streaming content).

### ChatStreamingState struct in @State (P2 — Backlog)
- Struct value-type: qualsiasi campo mutato invalida l'intera struct. Richiederebbe split in proprietà @State separate — refactor significativo.

### Conversation.messages COW trigger (P2 — Backlog)
- Array value-type inside struct. Qualsiasi mutazione al contenuto di un messaggio trigga COW dell'intero array. Richiederebbe reference-type wrapper — refactor architetturale.

### MarkdownContentView @AppStorage reads (P3 — Backlog)
- 4 @AppStorage reads per render. Minore impatto — UserDefaults è cachato in-process.

---

## File Modificati
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/ChatStore+RustBridge.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartS_End.swift`
- `App/SoloCodeApp/Sources/App/DesignSystem/DesignSystem+ViewHelpers.swift`
