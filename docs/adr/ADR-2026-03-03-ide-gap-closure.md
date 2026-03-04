# ADR-2026-03-03: Chiusura Gap Strutturali IDE (LSP, Debugger Nativo, Estendibilità, Hardening)

## Stato
Accepted - 2026-03-03

## Contesto

L'IDE ha una base solida su orchestrazione AI, tool runtime e pannelli operativi, ma presenta gap strutturali rispetto a capability classiche da IDE:

1. `LanguageService` assente (nessun adapter LSP nativo, fallback locale non incapsulato in servizio unico).
2. `DebugService` nativo assente (nessun ciclo DAP/LLDB con stato di sessione stabile collegato al `DebugPanel`).
3. Runtime estensioni/plugin non formalizzato (manifest, capability sandbox, lifecycle).
4. Debito tecnico aperto su indexing (`I13`, `I19`) e test UI snapshot dedicati (`I11`).

## Decisione

Adottare rollout incrementale a feature flag in 4 stream:

1. Language engine (`LanguageService` + `SourceKit-LSP` adapter + fallback index locale).
2. Native debug engine (`DebugService` + `DAP/LLDB` adapter + binding al `DebugPanel`).
3. Extension runtime minimo plugin-safe.
4. Hardening e QA con benchmark pre/post e checklist di regressione.

## Priorità Ufficiale Gap

- `P0`:
  - `LanguageService` con feature flag e fallback locale.
  - `DebugService` con breakpoints/step/watch/call stack.
  - `I13` IndexingTransaction con rollback centralizzato.
- `P1`:
  - Runtime estensioni con manifest/capability sandbox/load/unload.
  - `I19` riduzione I/O sync su incremental update.
- `P2`:
  - `I11` snapshot test UI instantgrep deduplicate.
  - Hardening esteso multi-provider e report benchmark comparativo.

## KPI di Successo

### KPI-L1 - Completion/Definition Latency
- Definizione:
  - `completion_latency_ms_p95`: tempo p95 tra richiesta completion e risposta.
  - `definition_latency_ms_p95`: tempo p95 go-to-definition.
- Baseline tecnica:
  - Path attuale: index locale/semantic + query simboli (no SourceKit-LSP nativo).
  - Stato baseline: da consolidare in benchmark locale ripetibile (`docs/benchmarks/IDE_GAP_KPI_BASELINE_2026-03-03.md`).
- Target:
  - `completion_latency_ms_p95 <= 120ms` su workspace medio.
  - `definition_latency_ms_p95 <= 90ms` su workspace medio.

### KPI-D1 - Debug Session Stability
- Definizione:
  - `debug_session_success_rate`: sessioni terminate senza crash/abort runtime.
  - `debug_recoverability_rate`: capacità di ripristino dopo timeout/errore adapter.
- Baseline tecnica:
  - Debug flow attuale prevalentemente orchestrativo/logico (`DebugStore`), senza adapter DAP/LLDB.
- Target:
  - `debug_session_success_rate >= 99%`.
  - `debug_recoverability_rate >= 95%`.

### KPI-I1 - Indexing Performance
- Definizione:
  - `index_full_duration_ms`: durata full index.
  - `index_incremental_duration_ms`: durata incremental update.
- Baseline tecnica:
  - Metriche già esposte da `CodebaseIndex.indexDurationMs`.
  - Gap noti: `I13` rollback transazionale, `I19` I/O sync in loop incrementale.
- Target:
  - `index_incremental_duration_ms` migliorato almeno del `20%` su dataset interno ripetibile.
  - Nessuno stato `.indexing` orfano in caso di failure/cancel.

## Conseguenze

### Positive
- Contratti chiari per language/debug/plugin runtime.
- Riduzione regressioni tramite KPI obbligatori e gate di hardening.
- Migliore evolvibilità del codice con moduli isolati (services/adapters).

### Negative
- Aumento complessità runtime (LSP/DAP process orchestration).
- Necessità di osservabilità aggiuntiva per latenza e failure mode.

## Rollout e Mitigazioni

- Feature flag obbligatori:
  - `language_service_enabled`
  - `language_sourcekit_lsp_enabled`
  - `debug_service_enabled`
  - `debug_dap_lldb_enabled`
  - `extensions_runtime_enabled`
- Fallback path:
  - Language: index locale se LSP non disponibile.
  - Debug: stato panel non bloccante e fallback logico.
- Gate merge:
  - test unit/integration verdi;
  - benchmark pre/post allegato;
  - checklist QA plan-flow completa.

## Aggiornamento 2026-03-04 (Stream Ownership I11/I13/I19)

Stato stream indexing/hardening consolidato con i seguenti deliverable:

- `I11` completato:
  - snapshot test UI dedicato su card InstantGrep deduplicate (`TaskActivityPanelInstantGrepSnapshotTests`).
- `I13` completato:
  - introdotto `IndexingTransaction` con rollback centralizzato stato/progress/queue per full e incremental indexing.
- `I19` completato:
  - pipeline `incrementalUpdate` convertita a batch async chunked per ridurre I/O sync nel loop actor.

Artifact operativi:

- Script benchmark ripetibile pre/post:
  - `scripts/benchmark_indexing_pre_post.sh --phase pre|post --tag <ID>`
- Checklist hardening dedicata:
  - `docs/hardening/INDEXING_HARDENING_CHECKLIST.md`
- Test rollback transazionale:
  - `CodebaseIndexIndexingTransactionTests`
