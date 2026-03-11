# P2 — I benchmark review-core non misurano ancora il loop completo della pipeline Rust

## Bug Fix Record
- Categoria: B
- Bug: i benchmark esistenti coprono verify/sync/projection/history, ma non il nuovo orchestratore step-based della pipeline review con callback Swift.
- Sintomo: mancano metriche dedicate su `pipeline_run`, `task_parse`, `re-review classification` e `callback roundtrip`.
- Impatto: la migrazione del loop review è verificata funzionalmente dai test, ma non ancora caratterizzata con benchmark dedicati.
- Gravita': media.
- Steps to reproduce:
  1. Eseguire i benchmark `docs/benchmarks/review-core/*`.
  2. Controllare il payload JSON.
  3. Osservare che non esistono ancora metriche specifiche della pipeline Rust completa.
- Risultato attuale: la tranche corrente deve essere documentata come funzionalmente valida ma con copertura benchmark incompleta.
- Risultato atteso: estendere `ValidationPerformanceTests` o una suite dedicata con metriche del nuovo orchestratore Rust.
- Causa probabile: priorità data al passaggio del loop e della compatibilità snapshot prima della telemetria performance.
- Scope consentito:
  - `Tests/CoderEngineTests/Validation/*`
  - `scripts/benchmark_review_pipeline_pre_post.sh`
  - `docs/benchmarks/review-core/*`
- Non-scope:
  - modifica della UI
  - refactor del panel
- Moduli confinanti da verificare:
  - `ReviewCoreBridge`
  - `ReviewPipelineRustDriver`
- Test da aggiungere o aggiornare:
  - benchmark `pipeline_run_p95_ms`
  - benchmark `task_parse_p95_ms`
  - benchmark `rereview_classification_p95_ms`
  - benchmark `callback_roundtrip_p95_ms`
- Strategia di fix minimo:
  - aggiungere misure dedicate senza cambiare il contratto della pipeline
  - riusare il marker `pre/post` già esistente per il loader Rust
- Verifica post-fix:
  - generazione di nuovi JSON benchmark in `docs/benchmarks/review-core/`
- Commit previsto: `test(review): add benchmark coverage for rust pipeline callbacks`
