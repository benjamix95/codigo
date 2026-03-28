# Changelog — Performance Audit Tool

**Data**: 2026-03-28
**Tipo**: Nuova feature (strumento integrato)
**Scope**: Audit pipeline, Performance analysis

---

## Sommario

Aggiunto un nuovo strumento di **Performance Audit** che analizza automaticamente l'app per colli di bottiglia, problemi di memoria, responsività UI, startup time e hot path. Lo strumento è **integrato nel flusso di analisi standard** — non viene eseguito da solo salvo richiesta esplicita dell'utente.

## Nuovi file

| File | Righe | Responsabilità |
|------|-------|----------------|
| `Engine/.../Audit/CodeReviewAuditService+Performance.swift` | ~290 | 5 audit tool Swift (bottlenecks, memory, UI responsiveness, startup, hot paths) |
| `Engine/.../Audit/AnalysisToolSelectionPolicy.swift` | ~120 | Policy auto-inclusione nei flussi di analisi |
| `Native/RustCore/src/review_audit/performance.rs` | ~280 | Implementazione Rust dei 5 tool |
| `Tests/.../Audit/PerformanceAuditTests.swift` | ~195 | Test Swift (11 test case) |
| `Tests/.../Audit/AnalysisToolSelectionPolicyTests.swift` | ~93 | Test policy (10 test case) |

## File modificati

| File | Modifica |
|------|----------|
| `CodeReviewAuditModels.swift` | Aggiunti `performanceTools`, 5 tool names, `ReviewAuditProfile.performanceDeep` |
| `CodeReviewAuditService.swift` | Registrato `rustBackedPerformanceTools` nel dispatch |
| `CodeReviewAuditService+Support.swift` | Profilo `performanceDeep`, perf tools in `iosPreflight`/`backendRegression`, self-exclusion |
| `review_audit/mod.rs` | Modulo `performance`, 5 test Rust |
| `review_audit/dispatch.rs` | Performance dispatch, `performance_deep_tools()` |
| `review_audit/meta.rs` | Profilo `performance_deep`, perf in profili esistenti |
| `review_audit/helpers.rs` | Aggiunto `read_file_lines` helper |
| `CoderIDECanonicalToolRegistry+Generated.swift` | 5 nuovi tool MCP registrati |
| `docs/performance-audit-tool.md` | Documentazione sviluppatore dedicata (nuovo) |

## 5 Tool di Performance Audit

1. **`audit_perf_bottlenecks`** — Rileva chiamate bloccanti (DispatchQueue.main.sync, Thread.sleep, usleep)
2. **`audit_perf_memory`** — Rileva problemi memoria (strong self, unowned, cache misuse, imageNamed)
3. **`audit_perf_ui_responsiveness`** — Rileva blocchi UI (main sync, JSON decode su main, FileManager su main)
4. **`audit_perf_startup`** — Rileva problemi startup (+load, constructor, eager init)
5. **`audit_perf_hot_paths`** — Rileva hot path (git churn + complessità, loop annidati, file grandi)

## Comportamento di integrazione

- **Analisi completa** ("analizza l'app", "audit completo"): include automaticamente tutti i 5 tool performance
- **Richiesta performance esplicita** ("controlla le performance"): esegue solo i 5 tool performance
- **Richiesta security/bug specifica**: esclude i tool performance
- **Tool singolo esplicito**: esegue solo il tool richiesto

## Profili aggiornati

| Profilo | Tool performance aggiunti |
|---------|--------------------------|
| `performanceDeep` (NUOVO) | Tutti e 5 |
| `iosPreflight` | UI responsiveness, memory, startup |
| `backendRegression` | Bottlenecks |

## Test

- **Rust**: 18 test performance (tutti passano) + 4 test preesistenti = **22/22 totale**
  - 5 Swift base: bottlenecks, memory, hot_paths, startup, ui_responsiveness
  - 4 Rust: thread_sleep, box_leak, lazy_static, (bottlenecks)
  - 3 TypeScript/JS: json_parse, setinterval, document_write
  - 2 Python: time_sleep, __del__
  - 2 Go: time_sleep, setfinalizer
  - 2 Context-aware: test_file_severity_downgrade, non_test_keeps_severity
  - 1 Profile: performance_deep_profile
- **Swift**: 11 test nuovi (PerformanceAuditTests) + 10 test policy (AnalysisToolSelectionPolicyTests)

## Miglioramenti multi-linguaggio (2026-03-28 update)

### Nuovi file
| File | Righe | Responsabilità |
|------|-------|----------------|
| `Native/RustCore/src/review_audit/tests_performance.rs` | 426 | Test dedicati performance audit (estratti da mod.rs) |

### Funzionalità aggiunte
- **Pattern multi-linguaggio**: ogni tool ora rileva pattern per Swift, Rust, TypeScript/JS, Python, Go
- **Language detection**: `helpers.rs` include `Lang` enum, `detect_language()`, `is_test_or_mock_file()`
- **Context-aware scoring**: test/mock file → severity ridotta a "suggestion", confidence ≤ 0.50
- **File structure**: test performance estratti in file separato per rispettare limite 500 righe

## Livelli avanzati — Churn, Config, Correlazione, Trending (2026-03-28 update)

### Nuovi file (Livello 2B, 2C, 3A, 3B)
| File | Righe | Responsabilità |
|------|-------|----------------|
| `Native/RustCore/src/review_audit/perf_churn.rs` | ~208 | Git churn integration — severity pesata per frequenza modifiche |
| `Native/RustCore/src/review_audit/perf_config.rs` | ~249 | Caricamento `.performance-audit.yml` — soglie configurabili |
| `Native/RustCore/src/review_audit/perf_correlate.rs` | ~249 | Correlazione cross-tool perf+bug — compound issue detection |
| `Native/RustCore/src/review_audit/perf_trending.rs` | ~358 | Baseline storica + delta report — new/resolved/regression tracking |

### File modificati
| File | Modifica |
|------|----------|
| `review_audit/mod.rs` | Esportati 4 nuovi moduli: `perf_churn`, `perf_config`, `perf_correlate`, `perf_trending` |
| `review_audit/dispatch.rs` | Registrati `audit_perf_correlate`, `audit_perf_trending` nel dispatch; aggiunta `performance_extended_tools()` |
| `review_audit/meta.rs` | Aggiunto profilo `performance_extended`/`performance_full` con tutti e 7 i tool |

### Livello 2B — Churn-weighted severity
- `FileChurnInfo`: struttura dati con commit count e days since last change
- `ChurnThresholds`: soglie configurabili (high=15, low=3, lookback=90 giorni)
- `collect_churn_data()`: raccoglie dati churn via `git log --name-only`
- `classify_churn()`: classifica file in High/Medium/Low
- `apply_churn_boost()`: suggestion→warning per High churn, confidence +0.10/+0.05
- `enrich_finding_with_churn()`: aggiunge metadata churn ai finding JSON
- **3 test unitari**: classify_churn_levels, churn_boost_upgrades_severity, enrich_finding_adds_churn_fields

### Livello 2C — Configurable thresholds
- `PerfAuditConfig`: configurazione completa con severity overrides, ignore patterns, exclude paths, min confidence, churn thresholds
- `load_perf_config()`: carica `.performance-audit.yml` dal workspace root
- Parser YAML semplificato (nessuna dipendenza esterna): supporta scalari, liste, mappe
- `is_excluded_path()`, `is_ignored_pattern()`: filtri configurabili
- **5 test unitari**: parse_empty, parse_basic, parse_severity_overrides, is_excluded_path, is_ignored_pattern

### Livello 3A — Cross-tool correlation
- `run_perf_correlate()`: esegue tutti i tool perf + bug/concurrency/error/state_machine/nil_crash
- Raggruppa finding per file, calcola correlation score composito
- Identifica **compound issues** (perf + bug nello stesso file) con severity boosted
- `compute_correlation_score()`: media ponderata con boost 1.3x per finding multi-tipo
- **4 test unitari**: correlation_score_both_present, correlation_score_only_perf, correlation_score_empty, max_severity_picks_highest

### Livello 3B — Trending/baseline storica
- `FindingSnapshot`: snapshot normalizzato per confronto (file + message fingerprint)
- `save_baseline()` / `load_baseline()`: persistenza in `.performance-audit-baseline.json`
- `compute_delta()`: calcola new, resolved, persistent, regression findings
- `run_perf_trending()`: produce report delta con status [NEW], [RESOLVED], [REGRESSION]
- Regressions: severity peggiorata → flaggato come critical
- **4 test unitari**: compute_delta_new_and_resolved, compute_delta_regression_detected, extract_snapshots_from_result, save_and_load_baseline_roundtrip

### Nuovi profili
| Profilo | Tool |
|---------|------|
| `performance_extended` / `performance_full` | Tutti e 7 (5 base + correlate + trending) |

### Test totali Rust
- **38/38 passati** (16 nuovi + 22 preesistenti), zero regressioni
