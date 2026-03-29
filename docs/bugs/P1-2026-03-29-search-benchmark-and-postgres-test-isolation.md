# P1 - benchmark semantic fragile e PostgreSQL dei test non isolato dal profilo utente

## Bug Fix Record
- Categoria: A
- Bug: il benchmark semantic MCP non riusciva sempre a risolvere il repo root e non produceva in modo affidabile l'artefatto JSON; inoltre, in contesto XCTest, la configurazione Postgres poteva cadere sul root `Application Support` dell'utente invece di isolarsi in `tmp`.
- Sintomo:
  - `coderide_benchmark_semantic_search` poteva fallire con `Unable to locate repository root for semantic benchmark`
  - il test benchmark smoke passava ma `manual-smoke.json` non veniva scritto
  - il Postgres in `~/Library/Application Support/CoderIDE/postgres` risultava avviato da processi XCTest con porta random, contaminando il data plane locale
- Impatto:
  - benchmark semantic non affidabile come strumento di misura
  - rischio di inquinare o bloccare il DB locale dell'utente durante i test
  - diagnostica del vettoriale resa ambigua da root/porta non coerenti
- Gravita: alta
- Steps to reproduce:
  1. Invocare `coderide_benchmark_semantic_search` da una sessione non ancorata chiaramente al repo.
  2. Osservare il fallimento sulla risoluzione del root oppure l'assenza dell'artefatto JSON.
  3. Eseguire test engine che toccano persistence senza helper espliciti.
  4. Osservare Postgres sotto `Application Support` con porta random di processo XCTest.
- Risultato attuale: benchmark fragile e persistence test non completamente isolata.
- Risultato atteso: benchmark semantic robusto nel trovare il repo e nel generare sempre un artefatto; contesto XCTest sempre isolato su root temporaneo salvo opt-in esplicito.
- Causa probabile:
  - `repo_root(...)` del benchmark semantic si affidava troppo al solo path workspace passato dal server
  - l'artefatto benchmark dipendeva da env propagation al test host, non sempre osservabile
  - `ManagedPostgresConfiguration.default` isolava i test solo con flag esplicito, lasciando casi non coperti sul root utente
- Scope consentito:
  - `Engine/CoderEngine/Sources/PersistenceCore/*`
  - `Native/CoderideMCPServerRust/src/benchmark_tools_semantic.rs`
  - test persistence / health check
- Non-scope:
  - migrazione schema DB
  - refactor del benchmark indexing/review
  - modifica del search ranking
- Moduli confinanti da verificare:
  - configuration default PostgreSQL
  - benchmark semantic MCP
  - search health check
- Test da aggiungere o aggiornare:
  - test Swift su root temporaneo in XCTest senza flag esplicito
  - test Rust su parsing durata benchmark / file count
  - aggiornamento regression test health check
- Strategia di fix minimo:
  - isolare sempre il root Postgres in XCTest salvo opt-in esplicito
  - aggiungere fallback robusti per repo root benchmark
  - garantire scrittura artifact benchmark anche senza env propagation verso xctest
- Verifica post-fix:
  - suite `PersistenceSchemaTests`
  - suite `UnifiedToolRuntimeTests` health check
  - benchmark semantic smoke con artefatto JSON prodotto
- Commit previsto: `fix(search): isolate test postgres and harden semantic benchmark`
