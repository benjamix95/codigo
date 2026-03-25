# P1: Markdown block-level elements not rendered during streaming

## Bug Fix Record
- Categoria: B — Importante
- Bug: Durante lo streaming, il contenuto markdown non viene renderizzato con block-level elements (headings, code blocks, liste, tabelle). Solo il testo inline viene mostrato.
- Sintomo: Mentre l'LLM risponde, il contenuto appare come testo plain con solo bold/italic/inline-code. Headings, code blocks fenced, liste puntate/numerate, tabelle non vengono renderizzati. Appena lo streaming termina, tutto il markdown viene renderizzato correttamente.
- Impatto: L'utente non vede la struttura del contenuto durante la risposta, rendendo difficile seguire risposte lunghe e strutturate.
- Gravita: P1 — degrada l'esperienza utente ma non rompe funzionalita' core
- Steps to reproduce: Chiedere all'LLM qualcosa che generi markdown strutturato (es. "dammi un piano con punti elenco e code blocks"). Osservare che durante lo streaming il contenuto e' flat text.
- Risultato attuale: `streamingBody` usa `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)` che renderizza solo inline markdown.
- Risultato atteso: Headings, code blocks, liste, tabelle renderizzati in tempo reale durante lo streaming.
- Causa probabile: `MarkdownContentView+Views.swift` usava `streamingBody` (inline-only) per tutto il contenuto streaming, senza distinzione.
- Scope consentito: `MarkdownContentView+Views.swift`
- Non-scope: `MarkdownContentView+Parsing.swift`, `MarkdownContentView+Renderers.swift`
- Moduli confinanti da verificare: ChatTurnView rendering performance, scroll behavior
- Test da aggiungere: Test per `hasBlockLevelMarkdown` detection
- Strategia di fix minimo:
  1. Aggiungere `hasBlockLevelMarkdown` per detectare velocemente se il contenuto ha block-level elements.
  2. Se si: usare `streamingFullMarkdownBody` che fa block parsing + cursore streaming.
  3. Se no: continuare con `streamingBody` (fast path inline-only).
- Verifica post-fix: Durante lo streaming, code blocks/headings/liste devono renderizzarsi in tempo reale.
- Commit previsto: fix(markdown): render block-level elements during streaming when detected
