# [P1] I blocchi reasoning possono generare ID duplicati nella timeline

## Bug Fix Record
- Categoria: A
- Bug: alcuni percorsi di ricostruzione della timeline producevano più blocchi `reasoning` con lo stesso `id`, generando warning `ForEach ... seg-reason-reasoning occurs multiple times`.
- Sintomo: warning ricorrente in console, rischio di risultati indefiniti SwiftUI nella timeline.
- Impatto: rendering non deterministico della chat e potenziale regressione nella cronologia.
- Gravità: alta
- Steps to reproduce:
  1. Costruire un `ChatTurnState` o blocchi persistiti con più segmenti reasoning.
  2. Lasciare `id: "reasoning"` costante su tutti.
  3. Renderizzare `ChatTurnView`.
- Risultato attuale: più segmenti `.reasoning` possono avere lo stesso ID.
- Risultato atteso: ogni blocco/segmento reasoning deve avere identità univoca pur preservando ordine e `sequence`.
- Causa probabile: `ChatTurnState.blocks` e i fallback di `resolvedTimelineBlocks` usavano ID reasoning costanti.
- Scope consentito: sanitizzazione identità blocchi timeline, ID dei segmenti interleavati, test su persistence/snapshot.
- Non-scope: layout della timeline, grouping tool, composer, sidebar.
- Moduli confinanti da verificare: `resolvedTimelineBlocks`, `ChatTurnState.blocks`, interleaver, test persistence.
- Test da aggiungere o aggiornare: sanitizer IDs, pipeline persistence con reasoning multipli.
- Strategia di fix minimo: sanitizzare gli `id` duplicati dei blocchi timeline e aggiungere difesa nel `segment.id` reasoning.
- Verifica post-fix: suite mirata timeline/pipeline persistence.
- Commit previsto: `fix(chat): sanitize duplicate reasoning timeline ids`
