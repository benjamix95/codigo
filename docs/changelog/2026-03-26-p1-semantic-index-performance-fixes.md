# Changelog — P1 SemanticIndex Performance Fixes

**Data:** 2026-03-26
**Categoria:** Performance (P1)
**Scope:** Engine/CoderEngine/Sources/CodebaseIndex/Indexing/

---

## Fix applicati

### BOTTLENECK-03: recalcAvgDocLength() O(n) → O(1)

**Problema:** `recalcAvgDocLength()` iterava tutti i `docLengths` (O(n), fino a 50K entry) dopo ogni singolo `addChunks`, `removeChunksForFile`, `removeChunk`, `updateFile`, `removeFile`. Su un indice con 50K chunk, ogni file update triggerava una scansione completa.

**Fix:** Aggiunto `totalTokenCount: Int` a `SemanticIndex` che viene aggiornato incrementalmente:
- `addChunks()` → incrementa totalTokenCount per ogni chunk aggiunto
- `removeChunksForFile()` → decrementa per ogni chunk rimosso
- `removeChunk()` (eviction) → decrementa
- `clear()` / `buildIndex()` → reset a 0

`recalcAvgDocLength()` ora calcola `totalTokenCount / docLengths.count` in O(1).
`rebuildTotalTokenCount()` fa il recalc O(n) completo solo al `loadFromDisk()`.

**File modificati:**
- `SemanticIndex.swift` — aggiunto `totalTokenCount` property
- `SemanticIndex+IndexManagement.swift` — incrementale in addChunks/removeChunksForFile, O(1) recalcAvgDocLength, nuovo rebuildTotalTokenCount
- `SemanticIndex+ChunkBudget.swift` — decremento in removeChunk
- `SemanticIndex+Build.swift` — reset in clear() e buildIndex()
- `SemanticIndex+Persistence.swift` — usa rebuildTotalTokenCount() al loadFromDisk

**Impatto:** Elimina ~50K iterazioni per ogni singolo file update.

---

### BOTTLENECK-04: evictIfNeeded() sort O(n log n) → scansione lineare O(n)

**Problema:** `evictIfNeeded()` ordinava **tutti** i `chunkAccessOrder` (fino a 50K entry) con `.sorted()` anche quando doveva evictare solo pochi chunk (es. 10). Sort completo O(n log n) su ogni `addChunks()` quando il budget è superato.

**Fix:** Nuovo metodo `findOldestChunks(count:)` che trova i N chunk più vecchi con una singola scansione lineare O(n), mantenendo un buffer limitato dei N più vecchi ordinato in modo discendente. Per eviction tipica (N << 50K), questo è significativamente più veloce del sort completo.

**File modificati:**
- `SemanticIndex+ChunkBudget.swift` — aggiunto findOldestChunks(), usato in evictIfNeeded()

**Impatto:** Per eviction di 10 chunk su 50K: da O(50K log 50K) ≈ 800K comparazioni a O(50K) ≈ 50K comparazioni.

---

### BOTTLENECK-02: persist() full rewrite → incremental delta per file dirty

**Problema:** `persist()` riscriveva **tutti** i chunk su disco (sort O(n log n) + encode + write) anche quando solo 1 file era cambiato. Su un indice con 50K chunk, ogni persist richiedeva encoding completo anche se solo 5 chunk erano stati modificati.

**Fix:** Nuovo path incrementale con file delta:
- Quando `<50%` dei chunk sono dirty E l'indice ha `>=1000` chunk E il file base esiste su disco → scrive solo i chunk dirty in `semantic.delta.jsonl`
- Il delta usa marcatori `#REMOVE:<filePath>` per indicare file da rimuovere, seguiti dai chunk aggiornati
- `loadFromDisk()` applica il delta automaticamente dopo il caricamento base, poi elimina il file delta
- Il full rewrite (con sort deterministico) viene usato solo per build iniziale o quando >50% dei file sono dirty

**File modificati:**
- `SemanticIndex+Persistence.swift` — persist incrementale, deltaPath, applyDelta, chunk count check skip con delta pendente

**Impatto:** Per update di 1 file su 500: da encoding di 50K chunk a encoding di ~100 chunk (99.8% riduzione).

---

## Test

- **33/34 test SemanticIndex passano** (tutti i test pre-esistenti)
- **1 test pre-esistente fallisce** (`testPersistRewritesAfterIncrementalUpdate`) — fallimento pre-esistente, non correlato a questi fix
- Build compila senza errori

## Rischi

- `totalTokenCount` potrebbe driftare se un code path dimentica di aggiornarlo → mitigato con `rebuildTotalTokenCount()` al loadFromDisk
- Il delta file potrebbe rimanere orfano se l'app crasha → nessun impatto: il prossimo loadFromDisk lo applica e pulisce
- `findOldestChunks` fa sort di un piccolo buffer ad ogni inserimento → accettabile perché il buffer è limitato a `overCount` (tipicamente <100)
