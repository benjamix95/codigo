# P1 - il vector store poteva restare vuoto in assenza di backend embedding nativo

## Bug Fix Record
- Categoria: A
- Bug: se CoreML model non era disponibile e la Rust FFI embeddings non era caricata, `EmbeddingService` ritornava `nil` e la pipeline non scriveva nulla in `semantic_embeddings`.
- Sintomo:
  - `search_health_check` mostrava DB vettoriale disponibile ma con `0` righe
  - `EmbeddingPipeline` completava senza righe salvate
  - `semantic_search` restava semantic/lexical-only anche con vector DB configurato
- Impatto:
  - beneficio del database vettoriale assente
  - backfill impossibile su workspace già indicizzati
  - search stack meno robusto fuori dal bundle app completo
- Gravita: alta
- Steps to reproduce:
  1. Usare un contesto senza `all-MiniLM-L6-v2.mlmodelc` e senza Rust FFI loaded.
  2. Indicizzare un workspace con `vectorSearchEnabled = true`.
  3. Osservare log `No embedding backend available` e `semantic_embeddings` vuota.
- Risultato attuale: il vector pipeline falliva silenziosamente a livello funzionale.
- Risultato atteso: anche senza backend nativo il sistema deve produrre embeddings deterministici di fallback e riempire il vector store.
- Causa probabile:
  - `EmbeddingBackendKind.pseudoHash` esisteva ma non veniva usato come fallback reale
  - nessun trigger di backfill quando l'indice semantico era già presente ma la tabella embeddings era vuota
- Scope consentito:
  - `Engine/CoderEngine/Sources/CodebaseIndex/Embeddings/*`
  - `Engine/CoderEngine/Sources/PersistenceCore/*`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/*`
  - test search/vector health
- Non-scope:
  - tuning del ranking vettoriale
  - sostituzione del modello embedding reale
  - UI timeline
- Moduli confinanti da verificare:
  - `EmbeddingService`
  - `EmbeddingIndexingPipeline`
  - backfill semantic search
  - `search_health_check`
- Test da aggiungere o aggiornare:
  - fallback pseudo-hash di `EmbeddingService`
  - vector backfill quando `semantic_embeddings` e' vuota
  - health check con conteggi embeddings
- Strategia di fix minimo:
  - introdurre backend pseudo-hash Swift sempre disponibile
  - schedulare backfill automatico alla prima `semantic_search` utile
  - esporre row/file count del vector store nella health diagnostics
- Verifica post-fix:
  - test unit embedding fallback
  - test runtime vector backfill
  - test health check search stack
- Commit previsto: `fix(search): backfill vector store with pseudo embeddings`
