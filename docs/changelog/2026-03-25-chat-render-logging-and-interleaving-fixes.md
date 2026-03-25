# 2026-03-25 — Chat render logging, interleaving fix, streaming markdown fix

## Summary

Aggiunto logging diagnostico completo per il rendering della chat principale,
fixato il bug del testo monolitico sopra i tool traces, e fixato il rendering
markdown block-level durante lo streaming.

## Changes

### 1. Chat Render Logger (`ChatRenderLogger.swift`) — NEW

Utility di logging basata su `os_log` per diagnosticare re-render SwiftUI.

- Subsystem: `com.solocode.render`, category: `chat`
- Throttling per label (0.25s) per evitare flood durante streaming
- API: `logRender()`, `logOnChange()`, `logEquatableMiss()`
- Attivabile/disattivabile via `ChatRenderLogger.isEnabled`
- Visibile in Console.app filtrando per `[RENDER]`, `[ONCHANGE]`, `[EQ-MISS]`

### 2. Render logging points aggiunti

- `ChatPanelView.rootLayout` — log ogni rebuild del root layout con panel state
- `messagesArea` — log con conversation id e loading state
- `messagesStack` — log con message count
- `chatMessageCell` — log per ogni cella con message id, role, streaming state
- `ChatTurnView.body` — log con segment count, trace count
- `ChatTurnView.==` — log DIAGNOSTICO che mostra QUALE campo ha causato il re-render (eq miss)
- `MessageRow.body` — log con role, streaming, editing state
- `MarkdownContentView.body` — log con streaming state e content length
- `MarkdownContentView.contentBody` — log del path scelto (streamingInline vs streamingFull)
- `Interleaver.segments` — log con block/tool/marker counts e monolithic detection
- onChange handlers: `streamContentVersion`, `messages.count`, `planningState`, `activeTaskConversationIds`

### 3. Fix: Testo monolitico sopra tool traces (P0)

**Root cause**: `appendToolTraceEvent()` non emetteva pipeline events al Rust
reducer. Il reducer non sapeva dei tool → `timeline_segments` vuoto → fallback
a singolo `primaryText` con `sequence: 0` → tutto il testo prima di tutti i tools.

**Fix (2 livelli)**:

- **Interleaver** (`ChatTurnTimelineInterleaver.swift`): quando detecta un singolo
  `primaryText` a `sequence: 0`, tool events con `sequence > 0`, e nessun
  `toolMarker` block, assegna al testo `maxToolSequence + 1`. Il testo appare
  dopo i tool traces (comportamento corretto per il caso comune: LLM usa tools
  poi scrive risposta).

- **Pipeline bridge** (`ChatPanelView+PartF_DebugTodoLifecycle.swift`): emette
  `toolTraceArtifact` pipeline event dopo ogni `appendToolTraceEvent()`. Questo
  fa si' che il Rust reducer chiami `ensure_tool_segment()` e splitti il testo
  in segmenti multipli con sequenze corrette.

### 4. Fix: Markdown non renderizzato durante streaming (P1)

**Root cause**: `MarkdownContentView` usava `streamingBody` (inline-only
`AttributedString` con `inlineOnlyPreservingWhitespace`) per TUTTO il contenuto
streaming. Block-level elements (headings, code blocks, liste, tabelle) non
venivano renderizzati fino al completamento.

**Fix** (`MarkdownContentView+Views.swift`):

- Aggiunto `hasBlockLevelMarkdown` — scan rapido delle prime 200 righe per
  detectare block-level markers (```, `#`, `- `, `> `, `|`).
- 3 path di rendering:
  1. **Streaming inline** (fast path): contenuto senza block-level → `streamingBody` originale
  2. **Streaming full** (new): contenuto con block-level → `streamingFullMarkdownBody`
     usa il block parser + cursore streaming dopo l'ultimo blocco
  3. **Completato**: `fullMarkdownBody` originale

## Files Changed

- `App/SoloCodeApp/Sources/Debug/Services/ChatRenderLogger.swift` — NEW
- `App/SoloCodeApp/Sources/ChatView/Root/ChatPanelView+RootLayout.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnView.swift`
- `App/SoloCodeApp/Sources/ChatView/Timeline/ChatTurnTimelineInterleaver.swift`
- `App/SoloCodeApp/Sources/ChatView/MessageRow/MessageRow.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartC_MessageHeader.swift`
- `App/SoloCodeApp/Sources/Services/ChatThread/Bindings/ChatPanelView+PartD_MessagesScroll.swift`
- `App/SoloCodeApp/Sources/Services/ChatTaskTrace/Bindings/ChatPanelView+PartF_DebugTodoLifecycle.swift`
- `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView.swift`
- `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Views.swift`

## Risks

- **Interleaver sequence override**: nel caso raro in cui il testo dovrebbe apparire
  PRIMA dei tools (es. messaggio di contesto iniziale), il fix lo sposta dopo.
  Mitigato dal fatto che quando il Rust pipeline emette toolMarkers correttamente,
  il codepath del "monolithic detection" viene bypassato.
- **Pipeline event aggiuntivo**: l'emissione di `toolTraceArtifact` per ogni tool
  trace potrebbe causare piu' pipeline events e piu' rebuilds. Mitigato dal
  throttling gia' esistente su `streamContentVersion`.
- **Streaming markdown performance**: il block parser durante streaming potrebbe
  essere piu' lento del path inline-only. Mitigato dal `cachedBlocks` e dal
  fatto che `hasBlockLevelMarkdown` attiva il full parser solo quando necessario.
