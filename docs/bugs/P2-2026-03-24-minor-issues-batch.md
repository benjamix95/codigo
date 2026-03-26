# P2-P3 — Batch di issue minori (Categoria C)

## C1 — write_lines perde trailing newline
- **File:** `debug_tools.rs:1201`
- **Problema:** `lines.join("\n")` non appende trailing newline. File sorgente perdono il newline finale dopo mark/clean/instrument.
- **Fix:** Appendere `"\n"` dopo il join.

## C2 — read_lines converte silenziosamente \r\n → \n
- **File:** `debug_tools.rs`
- **Problema:** Splitting su `\n` perde la distinzione Windows/Unix line endings. File Windows vengono convertiti silenziosamente.
- **Fix:** Preservare line endings originali o avvisare l'utente.

## C3 — JSON-RPC parse error usa ID 0 invece di null
- **File:** `server.rs:31`
- **Problema:** Lo spec MCP/JSON-RPC dice che quando l'ID non può essere determinato, deve essere null, non 0.
- **Fix:** Usare `JsonRpcId::Null` o equivalente.

## C4 — CATALOG_TOOL_COUNT hardcoded può driftare
- **File:** `catalog.rs:6`
- **Problema:** `CATALOG_TOOL_COUNT = 114` deve essere aggiornato manualmente quando si aggiungono tool. Il test lo cattura, ma se il test non gira il valore diverge.
- **Fix:** Calcolare il count a runtime o dal file `tool_names.txt`.

## C5 — family_for usa prefix matching inconsistente
- **File:** `catalog.rs:64`
- **Problema:** `starts_with("coderide_diagnostics")` senza trailing underscore matcha anche `coderide_diagnosticsfoo`.
- **Fix:** Aggiungere trailing underscore: `"coderide_diagnostics_"`.

## C6 — ISO8601DateFormatter allocato ad ogni chiamata
- **File:** `MCPSharedState.swift`
- **Problema:** Performance — formatter creato ad ogni invocazione di `normalizeTimestamp`, `canonicalTodo`, etc.
- **Fix:** Usare una proprietà `static let` per il formatter.

## C7 — Indice code review ricostruito da zero ad ogni write
- **File:** `MCPSharedState+CodeReviewIndex.swift`
- **Problema:** `_writeCodeReviewSnapshotUnsafe` chiama `rebuiltCodeReviewIndexUnsafe()` che legge TUTTI i file sessione. O(N) disk reads per ogni write.
- **Fix:** Mantenere l'indice in memoria e aggiornarlo incrementalmente.

## C8 — collisionIndex > 1 non genera suffisso per indice 1
- **File:** `SubagentExecutionIdentity.swift:37`
- **Problema:** `if let collisionIndex, collisionIndex > 1` — indice 1 produce no suffix, potenziale confusione naming.
- **Fix:** Cambiare a `> 0` o documentare la semantica.

## C9 — liveTextBuffer troncato a 2400 char con perdita dati
- **File:** `SubagentExecutionStream.swift:97`
- **Problema:** Testo più vecchio viene silenziosamente scartato. Chunk significativi possono andare persi.
- **Fix:** Aumentare il buffer o usare un ring buffer che preserva inizio e fine.

## C10 — SubagentExecutionRuntimeSettings usa static var mutabili senza sincronizzazione
- **File:** `SubagentExecutionSupport.swift:74`
- **Problema:** `static var` mutabili lette/scritte da qualsiasi thread. Data race in test.
- **Fix:** Usare `nonisolated(unsafe)` o actor-protect.
