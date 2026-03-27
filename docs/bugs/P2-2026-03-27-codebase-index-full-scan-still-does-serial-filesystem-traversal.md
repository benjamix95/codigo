## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: il full indexing del workspace continua a fare traversal filesystem e raccolta metadata in modo sincrono/seriale prima di arrivare alle parti parallele.
- Sintomo: `indexWorkspace()` entra in stato `.indexing`, poi ricostruisce per intero `fileTrees` e `allFileNodes` con `contentsOfDirectory`, sort ricorsivi e `attributesOfItem` per ogni file.
- Impatto: startup/index bootstrap piu' lenti sui repository grandi; il costo cresce con profondita' directory e numero file, indipendentemente dai file davvero sorgente da indicizzare.
- Gravita': P2
- Steps to reproduce:
  1. Aprire un workspace grande con molte directory e file.
  2. Lasciare partire l'indicizzazione iniziale.
  3. Misurare il tempo prima che il path passi dal rebuild dell'albero alla vera indicizzazione parallela.
- Risultato attuale:
  - `rebuildWorkspaceFileTrees()` azzera e ricostruisce tutto.
  - `buildFileTree(...)` esegue `fileExists`, `contentsOfDirectory`, ordinamenti e `attributesOfItem`.
  - solo dopo il rebuild completo parte la fase batch/parallela dei source file.
- Risultato atteso: il bootstrap dovrebbe limitare il lavoro sincrono upfront, usare traversal piu' economici/lazy e raccogliere metadata solo dove servono davvero.
- Causa probabile: architettura dell'indice ancora centrata su albero completo + flatten upfront, utile per funzionalita' multiple ma costosa come precondizione di ogni full scan.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/Support/CodebaseIndex+IndexingTransaction.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift`
- Non-scope:
  - redesign totale del `CodebaseIndex`
  - cambio di formato cache primario
  - refactor delle query simboli non legate al bootstrap
- Moduli confinanti da verificare:
  - file tree navigation
  - import graph
  - incremental update
  - cache reuse del symbol index
- Test da aggiungere o aggiornare:
  - benchmark dedicato al solo traversal filesystem
  - regressione sul bootstrap di workspace grande con molte directory escluse
- Strategia di fix minimo:
  - ridurre metadata fetch per file
  - anticipare il filtro directory/file esclusi
  - valutare enumerazione lazy invece di albero completo immediato
  - evitare rebuild totale quando basta una vista piu' mirata
- Verifica post-fix:
  - benchmark full indexing su workspace reale
  - smoke su navigation/import graph
- Commit previsto:
  - docs(perf): record codebase index filesystem traversal bottleneck

## Evidenze
- `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/CodebaseIndex+WorkspaceIndexing.swift:23-45`
- `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/Support/CodebaseIndex+IndexingTransaction.swift:20-24`
- `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Indexing/Support/CodebaseIndex+IndexingTransaction.swift:62-74`
- `Engine/CoderEngine/Sources/CodebaseIndex/Core/Operations/Helpers/CodebaseIndex+IndexHelpers.swift:4-100`
