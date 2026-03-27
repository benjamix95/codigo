# Changelog

Data: 2026-03-27
Tema: audit colli di bottiglia performance

## Modifiche

- eseguiti benchmark mirati review-core e review panel con `xcodebuild`
- consultati benchmark storici di indexing e review-core per confrontare i punti caldi gia' noti
- analizzati i path sorgente di `CodebaseIndex`, `ReviewCore`, `WorkspaceScanner` e le build phases Xcode
- documentati in priorita' i colli di bottiglia in `docs/bugs/2026-03-27-performance-bottlenecks-audit.md`

## Evidenze principali

- review-core benchmark corrente:
  - `verified_sync_p95_ms = 10.15`
  - `historical_shape_p95_ms = 4.37`
  - `projection_build_p95_ms = 1.00`
  - `security_gate_p95_ms = 2.14`
- review panel benchmark corrente:
  - `main_thread_block_time_ms = 1.43`
  - `history_load_p95_ms = 0.56`
  - `snapshot_ingest_p95_ms = 0.12`
- benchmark storico indexing:
  - `full_median_ms = 445`
  - `full_p95_ms = 452`

## Esito

- nessuna modifica applicativa eseguita in questo step
- audit pronto per il prossimo batch di fix mirati
