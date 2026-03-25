# P0: Chat text renders as monolithic block above tool traces

## Bug Fix Record
- Categoria: A — Critico
- Bug: Il testo dell'assistente viene renderizzato in un unico blocco monolitico sopra tutti i tool traces, invece di essere intervallato con essi.
- Sintomo: Quando l'LLM usa strumenti (edit, bash, read, ecc.), tutto il testo appare SOPRA i tool traces invece che intervallato: testo → tool → testo.
- Impatto: L'utente vede il risultato finale dell'LLM prima di vedere quali strumenti sono stati usati, rompendo il flusso logico della conversazione.
- Gravita: P0 — impatta la leggibilita' core della chat
- Steps to reproduce: Inviare una domanda che richieda l'uso di tool (es. "leggi questo file e fixalo"). Osservare che il testo dell'assistente appare tutto sopra i tool events.
- Risultato attuale: Un singolo blocco testo a `sequence: 0`, poi tutti i tool traces a sequence > 0.
- Risultato atteso: Testo prima dei tool → tool traces → testo dopo i tool, correttamente intervallato.
- Causa probabile: Due cause root:
  1. `appendToolTraceEvent()` non emetteva pipeline events, quindi il Rust reducer non sapeva che c'erano tool tra i segmenti di testo e non chiamava `ensure_tool_segment()`. Risultato: `timeline_segments` vuoto → fallback a singolo `primaryText` con `sequence: 0`.
  2. L'interleaver Swift non gestiva il caso "singolo blocco testo a sequence 0 + tool events a sequence > 0".
- Scope consentito: `ChatTurnTimelineInterleaver.swift`, `ChatPanelView+PartF_DebugTodoLifecycle.swift`
- Non-scope: Rust reducer, ChatTurnState, ChatPipelineCommitter
- Moduli confinanti da verificare: ChatTurnView rendering, ToolTraceStore ordering, ChatPipelineReducer
- Test da aggiungere: Test interleaver con singolo blocco testo seq=0 + tool events
- Strategia di fix minimo:
  1. **Interleaver fix**: quando c'e' un singolo `primaryText` a seq=0 e tool events con seq > 0 (senza toolMarker blocks), assegnare al testo `maxToolSequence + 1` cosi' appare DOPO i tools.
  2. **Pipeline event**: emettere `toolTraceArtifact` da `appendToolTraceEvent()` cosi' il Rust reducer puo' splittare il testo in segmenti multipli.
- Verifica post-fix: Il testo dell'assistente deve apparire dopo i tool traces quando ci sono tool events.
- Commit previsto: fix(chat): interleave text blocks with tool traces instead of monolithic rendering
