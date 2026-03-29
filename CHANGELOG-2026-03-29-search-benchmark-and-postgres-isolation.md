# Changelog - 2026-03-29 - search benchmark and postgres isolation

## Cosa ho cambiato
- isolato il root PostgreSQL di default in contesto XCTest su directory temporanea, evitando che test/benchmark possano usare `~/Library/Application Support/CoderIDE/postgres` salvo opt-in esplicito
- irrobustito `benchmark_semantic_search` lato Rust:
  - fallback multipli per trovare il repo root
  - generazione artifact JSON di fallback anche quando l'env non arriva al test host
  - parsing della durata test dal log xcode quando disponibile
  - passaggio della modalita' `full`/`smoke` via control file temporaneo, cosi' il benchmark non dipende piu' dal forwarding degli env verso xctest
- esteso `search_health_check` con `postgres_port` e `postgres_root` per rendere più trasparente il data plane del search stack

## Perché era necessario
- il benchmark semantic non era abbastanza affidabile come strumento operativo
- il DB Postgres reale dell'utente poteva essere contaminato da processi XCTest con porta random
- il vector DB appariva “strano” da ispezionare perché root e porta non erano chiaramente esposti

## Verifiche
- `CoderEngineTests/PersistenceSchemaTests`
- `CoderEngineTests/UnifiedToolRuntimeTests/testSearchHealthCheckReportsVectorAndTrigramStatus`
- smoke benchmark semantic via `xcodebuild` sul test sintetico
