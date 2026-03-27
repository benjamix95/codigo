# Changelog

Data: 2026-03-27
Tema: performance fixes runtime, search e build loop

## Modifiche

- introdotto fast-path locale nel sync review-core per ridurre il costo del bridge Swift/Rust sui payload piccoli
- spostati helper semantic search in file dedicato e aggiunto warmup background dell’indice con fallback testo durante il cold start
- aggiunta cache TTL per le scansioni git ripetute di `WorkspaceScanner`
- aggiunti helper per riuso contenuti/Merkle nel codebase indexing, limitati ai casi dove non peggiorano il full-build freddo
- ottimizzati gli script Rust di build con skip automatico quando artifact e sorgenti sono gia' allineati
- aggiunti test di regressione per Merkle snapshot indexed, semantic build senza re-read e cache git scans

## Benchmark

- review-core post-fix:
  - `verified_sync_p95_ms`: `10.15 -> 1.70`
  - `security_gate_p95_ms`: `2.14 -> 1.98`
  - `projection_build_p95_ms`: `1.00 -> 0.99`
- indexing smoke post-fix:
  - `full_median_ms`: `445 -> 459`
  - `full_p95_ms`: `452 -> 469`
  - `incremental_median_ms`: `8 -> 9`

## Nota

- il miglioramento principale e' sul review-core sync, che era il collo di bottiglia dominante
- il path indexing e' stato reso piu' efficiente sui reopen/hydration e nei set piccoli, ma il benchmark smoke cold-start resta sostanzialmente piatto e richiede ulteriore lavoro dedicato
