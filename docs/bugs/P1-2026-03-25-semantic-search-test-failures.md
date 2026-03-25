# P1 — Semantic Search Test Failures (pre-esistenti)

## Data: 2026-03-25

## Bug trovati durante l'esecuzione dei test SemanticIndexTests

### Bug 1: testSearchByExactSymbolName — Index out of range CRASH
- **Categoria**: A — Critico (crash)
- **Sintomo**: `Fatal error: Index out of range` in `ContiguousArrayBuffer.swift:692`
- **Impatto**: Crash durante la ricerca per nome simbolo esatto
- **Causa probabile**: Accesso a `results[0]` senza verificare che il risultato sia non-vuoto,
  oppure il backend di ricerca Rust restituisce indici fuori range nello snapshot
- **File**: `SemanticIndexTests+BuildAndSearch.swift:35` (test), probabile root in search backend

### Bug 2: testPersistAndReload — XCTAssertFalse failed
- **Categoria**: B — Importante
- **Sintomo**: Il persist/reload del semantic index non preserva correttamente i dati
- **File**: `SemanticIndexTests+Lifecycle.swift:100`

### Bug 3: testBuildIndexReadsNonUTF8ContentWithFallbackEncoding — XCTAssertFalse failed
- **Categoria**: B — Importante
- **Sintomo**: Il fallback encoding non funziona correttamente per file non-UTF8
- **File**: `SemanticIndexTests+Lifecycle.swift:245`

### Bug 4: testSearchBySynonym / testSearchByMeaning — Empty results
- **Categoria**: B — Importante
- **Sintomo**: Ricerche per sinonimo ("auth login flow") e significato ("save data") non trovano risultati
- **Causa probabile**: Il sistema di sinonimizzazione BM25 non espande correttamente i termini,
  o il Rust backend non supporta l'espansione sinonimi
- **File**: `SemanticIndexTests+BuildAndSearch.swift:47, 59`

### Bug 5: testSearchNaturalLanguageRanksAuthHandlerBeforeGenericHandler — Empty results
- **Categoria**: B — Importante
- **Sintomo**: "where is auth handled" non trova nessun risultato
- **File**: `SemanticIndexTests+BuildAndSearch.swift:168-169`

### Bug 6: testUpdateFileUpdatesIndex — XCTAssertFalse failed
- **Categoria**: B — Importante
- **Sintomo**: L'aggiornamento incrementale di un singolo file non aggiorna l'indice correttamente
- **File**: `SemanticIndexTests+Lifecycle.swift:47`

## Nota
Tutti questi bug erano pre-esistenti e NON sono regressioni delle modifiche fatte in questa sessione.
I nuovi test (IndexFeatureFlagsTests, ExcludedDirectoriesTests, allChunks tests) passano tutti al 100%.
