## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la persistenza/caricamento dell'indice semantico mantiene path costosi di serializzazione full snapshot e lettura completa in memoria.
- Sintomo: `persist()` ordina tutti i chunk, li encoda in `[String]`, fa `joined(separator:)` e scrive tutto in un colpo; `loadFromDisk()` legge l'intero JSONL come `String`, fa split di tutte le linee e ricostruisce i chunk in memoria.
- Impatto: picchi di CPU/memoria e tempi piu' alti su workspace grandi, soprattutto su primo load, rebuild completi o compaction.
- Gravita': P2
- Steps to reproduce:
  1. Costruire un indice semantico grande.
  2. Forzare persistenza o reload da disco.
  3. Osservare crescita di memoria e lavoro seriale sull'actor dell'indice.
- Risultato attuale:
  - il path full rewrite rimane costoso quando non scatta la delta persistence.
  - il load ricostruisce tutto a partire da una `String` completa del file.
  - il lavoro resta concentrato nel runtime dell'indice invece di essere streammato.
- Risultato atteso: persistenza e load dovrebbero minimizzare allocazioni e rewrite completi, soprattutto per indici molto grandi.
- Causa probabile: formato JSONL semplice e deterministico ma ancora gestito con operazioni bulk in memoria.
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift`
  - `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift`
- Non-scope:
  - cambio radicale di formato storage
  - introduzione immediata di DB/vector store esterni
  - redesign della semantica di `SemanticChunk`
- Moduli confinanti da verificare:
  - delta persistence
  - metadata/simHash
  - load/build lifecycle
  - cache compatibilita' test
- Test da aggiungere o aggiornare:
  - benchmark persist/load con indice grande
  - test di memoria o almeno limite size-based
  - regressione sulla correttezza di delta + full compaction
- Strategia di fix minimo:
  - stream write/read invece di costruire l'intero payload in memoria
  - spostare le operazioni bulk piu' pesanti fuori dal path caldo dell'actor
  - rendere piu' aggressivo il path incremental dove sicuro
- Verifica post-fix:
  - benchmark persist/load
  - confronto peak memory prima/dopo
- Commit previsto:
  - docs(perf): record semantic index persistence bottleneck

## Evidenze
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift:39-113`
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift:185-260`
- `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Build.swift:81-89`
