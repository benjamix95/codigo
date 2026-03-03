# Deep Scan TODO (2026-03-03)

## Bug Hunt (50)

- [x] B01 `CodebaseIndex+IndexHelpers.swift` evitare incremento `totalSymbolsExtracted` su simboli duplicati nello stesso file
- [x] B02 `CodebaseIndex+SingleFileIndexing.swift` rimuovere chunk semantic stale quando file sparisce prima dell'upsert realtime
- [x] B03 `CodebaseIndex+SingleFileIndexing.swift` rimuovere chunk semantic stale quando lettura attributi file fallisce
- [x] B04 `CodebaseIndex+SingleFileIndexing.swift` rimuovere chunk semantic stale quando `SymbolExtractor.indexFile` ritorna `nil`
- [x] B05 `CodebaseIndex+WorkspaceIndexing.swift` rispettare `excludedPaths` anche in `incrementalUpdate`
- [x] B06 `CodebaseIndex+WorkspaceIndexing.swift` rispettare `.gitignore` anche in `incrementalUpdate`
- [x] B07 `CodebaseIndex+WorkspaceIndexing.swift` rimuovere da semantic index i file che falliscono il reindex incrementale
- [x] B08 `CodebaseIndex+SingleFileIndexing.swift` `clear()` deve resettare `excludedFilePatterns`
- [x] B09 `CodebaseIndex+SingleFileIndexing.swift` `clear()` deve resettare `gitignoreRules`
- [x] B10 `CodebaseIndex+SingleFileIndexing.swift` `clear()` deve resettare `respectGitignore`
- [x] B11 `CodebaseIndex+SingleFileIndexing.swift` `clear()` deve resettare `_indexingProgress`
- [x] B12 `EventNormalizer+SearchParsing.swift` se `previewLines` è vuoto usare `matchesCount` riportato invece di forzare 0
- [x] B13 `EventNormalizer+SearchParsing.swift` supportare comandi grep con prefisso env (`NO_COLOR=1 rg ...`)
- [x] B14 `ToolSchemaCatalog+IndexTools.swift` allineare required aliases di `find_references` ai test/runtime (query/name)
- [x] B15 `UnifiedToolRuntime+IndexSemantic.swift` rendere stabile il dettaglio quando la fonte è solo grep fallback
- [x] B16 `UnifiedToolRuntime+IndexSemantic.swift` usare workspace paths risolti anche se `workspaceContext.workspacePaths` è vuoto
- [x] B17 `UnifiedToolRuntime+IndexSemantic.swift` dopo wait indexing rieseguire check reindex su stato aggiornato
- [x] B18 `UnifiedToolRuntime+SemanticHybridSources.swift` deduplicare hit grep fallback per `file:line`
- [x] B19 `UnifiedToolRuntime+SemanticHybridSources.swift` evitare grep su percorsi non esistenti
- [x] B20 `UnifiedToolRuntime+SemanticHybridSources.swift` limitare cardinalità hit fallback per evitare esplosioni su query larghe
- [x] B21 `EventNormalizer+SearchParsing.swift` parse `path:line:` robusto anche con percorsi `:` (es. Windows drive)
- [x] B22 `EventNormalizer+SearchParsing.swift` `parseReadActivityFromCommand` ora copre `awk`, `less`, `more`
- [x] B23 `EventNormalizer+SearchParsing.swift` tokenizer shell gestisce escaping regex/backslash senza perdere token
- [x] B24 `EventNormalizer+SearchParsing.swift` supporto output null-separated (`--null/-z`) + test regressivo parser
- [x] B25 `TaskActivityStore+Buffering.swift` dedup instantgrep ora normalizza scope multipli (`a,b` == `b,a`)
- [ ] B26 `TaskActivityStore+Buffering.swift` assenza TTL specifico per card instantgrep stale
- [x] B27 `UnifiedToolRuntime+IndexSemantic.swift` fallback tokenizzazione per query tecniche non alfanumeriche (`C++`, `C#`, ecc.)
- [x] B28 `UnifiedToolRuntime+IndexSemantic.swift` `searchPaths` canonicalizzati e deduplicati
- [x] B29 `UnifiedToolRuntime+IndexSemantic.swift` `min_confidence` validato su input non-finite (`NaN`)
- [ ] B30 `UnifiedToolRuntime+SemanticHybridFusion.swift` tie-break potrebbe penalizzare match semantic ad alta qualità ma rank tardivo
- [x] B31 `UnifiedToolRuntime+SemanticHybridSources.swift` pattern grep deduplicati
- [ ] B32 `UnifiedToolRuntime+SemanticHybridSources.swift` `grepConfidence` poco discriminante su snippet lunghi
- [ ] B33 `UnifiedToolRuntime+IndexSemantic.swift` output detail usa raw source keys poco UX-friendly
- [ ] B34 `SemanticIndex+Search.swift` bonus su doc comment può favorire chunk comment-only rispetto a implementazioni
- [ ] B35 `SemanticIndex+Search.swift` punteggio filename può sovrapesare directory noise in monorepo grandi
- [ ] B36 `SemanticIndex+Build.swift` fallback `String(contentsOfFile:)` non gestisce encoding non UTF-8
- [ ] B37 `SemanticIndex+Build.swift` `incrementalUpdate` usa rebuild Merkle completo anche con pochi file cambiati
- [x] B38 `SemanticIndex+Persistence.swift` persist JSONL deterministico per ordine chunk
- [ ] B39 `SemanticIndex+Persistence.swift` metadata non include fingerprint di config tokenizer/synonyms
- [ ] B40 `SemanticIndex+Lexicon.swift` synonym expansion non evita loop semantici per query rumorose
- [ ] B41 `CodebaseIndex+WorkspaceIndexing.swift` `.gitignore` caricato solo dal primo root in multi-root
- [ ] B42 `CodebaseIndex+WorkspaceIndexing.swift` progress incrementale non esposto durante `incrementalUpdate`
- [ ] B43 `CodebaseIndex+WorkspaceIndexing.swift` nessun reset difensivo status in caso di abort durante index
- [ ] B44 `CodebaseIndex+RealtimeQueue.swift` queue sostituisce eventi su stessa path senza mantenere timestamp causale
- [ ] B45 `FileWatcher.swift` debounce globale per tutte le path può ritardare update su file hot
- [ ] B46 `FileWatcher.swift` mancano metriche sulle path droppate dal filtro estensione
- [x] B47 `CodebaseIndex+IndexHelpers.swift` `buildImportGraph` deduplica import ripetuti
- [x] B48 `CodebaseIndex+SingleFileIndexing.swift` `indexSingleFile` verifica `maxFileSize` nel realtime upsert
- [x] B49 `CodebaseIndex+SingleFileIndexing.swift` `indexSingleFile` applica filtro estensione indexable
- [x] B50 `CodebaseIndex+Diagnostics.swift` `totalFiles` ora conta solo nodi file (non directory)

## Bug Hunt (extra round)

- [x] B51 `UnifiedToolRuntime+IndexSemantic.swift` validare `target_directories` assoluti fuori workspace (bloccare scope escape)
- [x] B52 `UnifiedToolRuntime+IndexSemantic.swift` bloccare traversal relativi (`../`) fuori workspace
- [x] B53 `UnifiedToolRuntime+SemanticHybridSources.swift` applicare filtro `searchPaths` anche alla sorgente `symbolIndex`
- [x] B54 `UnifiedToolRuntime+SemanticHybridSources.swift` usare root workspace come `cwd` del grep fallback (evita failure su file path)
- [x] B55 `UnifiedToolRuntime+IndexSemantic.swift` ramo fallback `grep` allineato con esclusioni (`.git`, `.build`, `node_modules`)
- [x] B56 `SemanticIndex+Persistence.swift` load raggruppato per file per preservare mappa `fileToChunks` completa
- [x] B57 `CodebaseIndex+WorkspaceIndexing.swift` incremental update non salta più change reali quando `mtime` non avanza ma hash cambia
- [x] B58 `CodebaseIndex+WorkspaceIndexing.swift` progress incrementale aggiornato anche sui casi `content unchanged`
- [x] B59 `FileWatcher.swift` estensioni watcher allineate a `CodebaseIndex.indexableExtensions`
- [x] B60 `FileWatcher.swift` filtro hidden applicato a tutti i componenti path, non solo al basename
- [x] B61 `FileWatcher.swift` `FSEventStreamStart` ora gestisce failure con rollback stato/risorse
- [x] B62 `FileWatcher.swift` `enqueueChanges` ignora callback tardive dopo `stop()`
- [x] B63 `EventNormalizer+SearchParsing.swift` supporto wrapper shell `bash -lc 'rg ...'`
- [x] B64 `EventNormalizer+SearchParsing.swift` supporto comandi assoluti (`/usr/bin/rg ...`)
- [x] B65 `EventNormalizer+SearchParsing.swift` parsing query ignora flag con valore (`--include`, `--ignore-file`, ecc.)
- [x] B66 `EventNormalizer+SearchParsing.swift` parsing output heading-mode (`file` + `line:preview`) e fallback `stderr`

## Miglioramenti (20+)

- [ ] I01 aggiungere benchmark sintetico `semantic_search` su workspace 10k file
- [ ] I02 introdurre telemetry counters per ratio semantic/symbol/grep source usage
- [ ] I03 aggiungere `semantic_search` explain mode (`show_scoring=true`)
- [ ] I04 serializzare in metadata versione `synonymMap`/`stopWords`
- [ ] I05 cache LRU per risultati grep fallback per query ripetute
- [x] I06 supportare `target_directories` come array JSON oltre CSV
- [x] I07 validare percorsi target contro workspace consentiti con errore/feedback esplicito
- [ ] I08 supportare opzione `semantic_search` strict-scope (no grep outside scope)
- [ ] I09 aggiungere test proprietà (property-based) per parser grep output
- [ ] I10 aggiungere fuzz test su `parseSearchQueryFromCommand`
- [ ] I11 aggiungere snapshot test UI per cards instantgrep deduplicate
- [ ] I12 introdurre cap configurabile per `instantGreps` nel TaskActivityStore
- [ ] I13 introdurre `IndexingTransaction` con rollback status/state centralizzato
- [ ] I14 aggiungere circuit breaker su fallback grep in repository enormi
- [ ] I15 aggiungere timeout dinamico grep in base a dimensione workspace
- [ ] I16 aggiungere cancellazione cooperativa in `buildIndex` batch loop
- [ ] I17 aggiungere metriche di drift tra `matchesCount` provider e parsed preview
- [ ] I18 normalizzare output detail semantic in etichette localizzabili
- [ ] I19 ridurre I/O sync su `incrementalUpdate` con pipeline chunked async
- [ ] I20 estendere integration tests multi-root con `.gitignore` per-root
- [x] I21 aggiungere test regressione su reorder deterministico `persist` semantic JSONL
- [ ] I22 aggiungere logging strutturato per queue flush realtime (batch size, duration)
- [ ] I23 introdurre health check command per pipeline search end-to-end

## Note operative

- Obiettivo sprint successivo: chiudere almeno 30 item bug pending + 12 improvement.
- Ogni fix deve avere test regressivo o motivazione documentata.
