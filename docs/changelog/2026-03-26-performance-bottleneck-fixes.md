# Changelog — 2026-03-26 Performance Bottleneck Fixes

## Summary

Fix di 3 colli di bottiglia P0 identificati nell'analisi di performance del 2026-03-26.

---

## Fix 1 — HybridSearchEngineBackend: Thread+Semaphore per query (P0)

**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift`

**Problema**: `mergeWithVectorSync()` creava un nuovo kernel `Thread` + 2 `DispatchSemaphore` nested per ogni singola ricerca hybrid. Causava:
- Allocazione kernel thread per query (+200-2000ms overhead)
- Rischio deadlock con 2 semaphore nested (inner + outer)
- Pool starvation sotto carico

**Fix**: Sostituito con 1 `Task.detached` + 1 `DispatchSemaphore`. Nessun `Thread` allocato. Il `defer { semaphore.signal() }` garantisce segnalazione anche in caso di errore. Aggiunta helper class `SendableBox<T>` riutilizzabile.

**Impatto**: Eliminato overhead kernel thread (~200ms/query), eliminato rischio deadlock nested semaphore.

---

## Fix 2 — Rust Negative Query: re-tokenizzazione O(n*m) (P0)

**File**: `Native/RustCore/src/scoring.rs`

**Problema**: Quando la query conteneva token negativi (es. "hello -world"), il codice chiamava `tokenize_query()` sul `contextualized_text` di OGNI chunk rimasto nello score set. Con 50K chunk, questo causava O(n*m) tokenizzazioni.

**Fix**: Sostituito con lookup diretto nell'`inverted_index` già presente nel payload. Per ogni token negativo, raccoglie i chunk_id dalle postings e li esclude. Complessità: O(k*p) dove k=token negativi (1-3), p=postings per token.

**Impatto**: Da O(50K * avg_text_length) a O(3 * avg_postings). Ordini di grandezza più veloce.

**Test**: 4 test di regressione Rust aggiunti — tutti passati.

---

## Fix 3 — SemanticIndex Persist: full serialize O(n) (P0)

**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+Persistence.swift`
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex.swift`
**File**: `Engine/CoderEngine/Sources/CodebaseIndex/Indexing/SemanticIndex+IndexManagement.swift`

**Problema**: `persist()` serializzava TUTTI i 50K chunk ad ogni chiamata:
1. Sort O(n log n) per filePath/startLine
2. JSON encode di ogni chunk
3. Join + write atomica dell'intero file

Questo veniva triggerato dal debounce timer (2s) anche senza modifiche.

**Fix**:
- Aggiunto `dirtyFilePaths: Set<String>` nell'actor SemanticIndex
- `addChunks()` e `removeChunksForFile()` marcano il filePath come dirty
- `persist()` fa early return se `dirtyFilePaths.isEmpty` e il file esiste su disco
- Dopo write completo, `dirtyFilePaths.removeAll()` resetta il set
- Estratto `persistMetadata()` come funzione separata (sempre veloce, ~1KB)

**Impatto**: Persist successive senza modifiche sono no-op (~0ms vs ~500ms per 50K chunk).

**Test**: 2 test di regressione Swift aggiunti.

---

---

## Test di regressione aggiunti

### Rust (4 test — `Native/RustCore/src/scoring.rs`)
- `test_negative_query_excludes_matching_chunks` — verifica che token negativi escludano chunk corretti via inverted index
- `test_negative_query_empty_inverted_index` — nessun crash se inverted index manca il token
- `test_negative_query_all_excluded` — tutti i chunk esclusi → risultato vuoto
- `test_negative_query_no_negative_tokens` — query senza negativi → nessun filtro applicato

**Risultato:** 4/4 passed, `cargo test` clean.

### Swift (2 test — `Tests/CoderEngineTests/SemanticSearch/SemanticIndexTests+Lifecycle.swift`)
- `testPersistSkipsRewriteWhenNotDirty` — verifica che persist() non riscriva il file se nessun chunk è stato modificato
- `testPersistWritesWhenDirtyAfterAddChunks` — verifica che addChunks() marchi dirty e persist() scriva effettivamente

---

## Bottleneck P1 differiti (4 item)

| # | Area | Motivo differimento |
|---|------|---------------------|
| 4 | `persistSnapshot()` per-evento | Coalescing via `DispatchQueue.main.async` già sufficiente |
| 5 | ChatPanelView 18 @EnvironmentObject | Snapshot caching già implementato; refactor architetturale troppo ampio |
| 6 | RustBridge round-trip Swift↔Rust | Richiede implementazione delta protocol FFI — task separato |
| 7 | TodoStore `saveTodos()` sincrono | Già mitigato con flock skip su main thread (commit `134f030d0`) |

## Bottleneck P2-P3 differiti (6 item)

| # | Priorità | Area | Motivo differimento |
|---|----------|------|---------------------|
| 8 | P2 | EventBus prune inline | Throttle 5s esistente sufficiente |
| 9 | P2 | SemanticIndex batch size fisso | Funzionale, non bloccante |
| 10 | P2 | SequenceGenerator actor conteso | Impatto basso, misurabile solo con profiling |
| 11 | P2 | Doppio record task lifecycle | Refactor non urgente, nessun impatto UX |
| 12 | P3 | addChunks sequenziale post-batch | Overhead marginale rispetto a I/O parsing |
| 13 | P3 | scheduleSnapshotFlush GCD overhead | Non percepibile dall'utente |

---

## Metriche attese post-fix

| Bottleneck | Prima | Dopo | Riduzione stimata |
|------------|-------|------|-------------------|
| HybridSearch per-query | Thread alloc ~200-2000ms | Task.detached ~0-5ms | ~97% |
| SemanticIndex persist (no-op) | ~500ms (50K chunk rewrite) | ~0ms (early return) | ~100% |
| Rust negative query (10K chunk) | O(10K * tokenize) ~200ms | O(k * postings) ~1ms | ~99% |

---

## File modificati

| File | Tipo modifica | Delta |
|------|---------------|-------|
| `HybridSearchEngineBackend.swift` | Fix Thread→Task.detached + SendableBox | +28 / -17 |
| `scoring.rs` | Fix re-tokenizzazione→inverted index + 4 test | +119 / -21 |
| `SemanticIndex+Persistence.swift` | Fix dirty tracking + persistMetadata() | +30 / -5 |
| `SemanticIndex.swift` | Aggiunto campo dirtyFilePaths + debounce | +8 / -0 |
| `SemanticIndex+IndexManagement.swift` | Dirty tracking in addChunks/removeChunks | +2 / -0 |
| `SemanticIndexTests+Lifecycle.swift` | 2 test regressione dirty tracking | +75 / -0 |
| **Totale** | | **+270 / -35** |

---

## Riferimento analisi completa

Vedi: [`docs/bugs/ARCH-2026-03-26-performance-bottlenecks.md`](../bugs/ARCH-2026-03-26-performance-bottlenecks.md) per l'analisi dettagliata di tutti i 13 colli di bottiglia con suggerimenti di fix.
