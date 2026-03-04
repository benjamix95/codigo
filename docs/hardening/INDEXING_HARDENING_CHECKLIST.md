# Indexing Hardening Checklist (I11 / I13 / I19)

Checklist operativa per validare hardening dello stream ownership su indexing + InstantGrep UI.

## 1) Test Funzionali Minimi

- [ ] `cd CoderEngine && swift test --filter CodebaseIndexIncrementalTests`
- [ ] `cd CoderEngine && swift test --filter CodebaseIndexIndexingTransactionTests`
- [ ] `swift test --filter TaskActivityStoreInstantGrepTests`
- [ ] `swift test --filter TaskActivityPanelInstantGrepSnapshotTests`
- [ ] `swift test --filter TaskActivityVisibilityTests`

## 2) KPI Benchmark Pre/Post (ripetibile)

- [ ] Eseguire baseline `pre`:
  - `scripts/benchmark_indexing_pre_post.sh --phase pre --tag <ID>`
- [ ] Eseguire run `post` con stesso tag:
  - `scripts/benchmark_indexing_pre_post.sh --phase post --tag <ID>`
- [ ] Verificare generazione summary:
  - `docs/benchmarks/indexing-hardening/<ID>-summary.md`

## 3) Criteri di Accettazione

- [ ] Nessuno stato `.indexing` orfano dopo cancellation (`IndexingTransaction` rollback).
- [ ] `incrementalUpdate` usa pipeline chunked async e mantiene consistenza semantic index.
- [ ] UI InstantGrep mostra card deduplicate e limite card stabile (snapshot test).
- [ ] Report benchmark pre/post allegato con delta esplicito su `incremental_median_ms`.

## 4) Note Esecuzione

- Usare lo stesso `--tag` per correlare `pre`/`post`.
- Ripetere benchmark su macchina non in carico I/O elevato.
- Conservare i JSON raw in `docs/benchmarks/indexing-hardening/` per audit.
