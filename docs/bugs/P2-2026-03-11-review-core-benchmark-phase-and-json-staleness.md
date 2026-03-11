# P2 — Il benchmark review-core poteva riportare JSON stantii e non distinguere davvero pre/post

## Bug Fix Record
- Categoria: B
- Bug: lo script benchmark review-core poteva lasciare JSON precedenti sul disco e il test engine non distingueva con affidabilita' la fase `pre` da `post`.
- Sintomo: report `summary.md` incoerenti rispetto ai log reali, `pre` e `post` entrambi sul path Rust oppure valori obsoleti riutilizzati.
- Impatto: benchmark non affidabile per decidere il rollout della tranche Rust.
- Gravita': media
- Steps to reproduce:
  1. Eseguire `scripts/benchmark_review_pipeline_pre_post.sh --phase pre`.
  2. Eseguire `scripts/benchmark_review_pipeline_pre_post.sh --phase post`.
  3. Confrontare i JSON salvati con le righe `REVIEW_ENGINE_BENCHMARK` nei log.
- Risultato attuale: i JSON devono sempre essere rigenerati dal run corrente e la fase `pre/post` deve essere leggibile dal test host senza dipendere da env non propagati.
- Risultato atteso: `pre` su fallback Swift e `post` su path Rust osservabile, con summary allineato ai log.
- Causa probabile: JSON non sovrascritti e assunzione errata che tutte le env custom di `xcodebuild` fossero visibili al processo test.
- Scope consentito:
  - `scripts/benchmark_review_pipeline_pre_post.sh`
  - `Tests/CoderEngineTests/Validation/ValidationPerformanceTests.swift`
- Non-scope:
  - benchmark infrastrutturali non-review
  - CI remoto
- Moduli confinanti da verificare:
  - `ReviewCoreBridge.loadedState`
  - artefatti `docs/benchmarks/review-core/`
- Test da aggiungere o aggiornare:
  - benchmark smoke con `phase` marker su filesystem
- Strategia di fix minimo:
  - cancellare i JSON vecchi a inizio run
  - ricostruire sempre i JSON dal log corrente
  - usare un phase marker file nel repo per distinguere `pre` e `post`
- Verifica post-fix:
  - `scripts/benchmark_review_pipeline_pre_post.sh --phase pre --tag review-core-tranche2`
  - `scripts/benchmark_review_pipeline_pre_post.sh --phase post --tag review-core-tranche2`
- Commit previsto: `test(review): harden review-core benchmark phase separation`
