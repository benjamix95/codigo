# Performance Audit Tool — Documentazione sviluppatore

**Creato**: 2026-03-28
**Tipo**: Strumento integrato di analisi performance
**Moduli**: Rust (`review_audit/performance.rs`) + Swift (`CodeReviewAuditService+Performance.swift`)

---

## Panoramica

Il Performance Audit Tool è un sistema di analisi statica delle performance composto da **5 tool** che rilevano colli di bottiglia, problemi di memoria, responsività UI, startup time e hot path nel codebase.

### Caratteristica chiave: integrazione automatica

Lo strumento **non viene eseguito da solo** per default. È integrato nel flusso di analisi standard tramite `AnalysisToolSelectionPolicy`:
- **Analisi completa** ("analizza l'app", "audit completo") → include automaticamente tutti i 5 tool
- **Richiesta performance esplicita** ("controlla le performance") → esegue solo i 5 tool
- **Richiesta specifica** (security, bug) → esclude i tool performance
- **Tool singolo esplicito** → esegue solo il tool richiesto

---

## I 5 Tool

### 1. `audit_perf_bottlenecks`

**MCP**: `coderide_audit_perf_bottlenecks`
**Rileva**: chiamate bloccanti su main thread

Pattern cercati:
- `DispatchQueue.main.sync`
- `Thread.sleep`
- `usleep`
- Chiamate sincrone pesanti nel main thread

### 2. `audit_perf_memory`

**MCP**: `coderide_audit_perf_memory`
**Rileva**: problemi di gestione memoria

Pattern cercati:
- `strong self` in closure (retain cycle potenziale)
- `unowned` (crash se deallocato)
- Cache senza limiti (`NSCache` senza `countLimit`/`totalCostLimit`)
- `UIImage(named:)` senza cache management

### 3. `audit_perf_ui_responsiveness`

**MCP**: `coderide_audit_perf_ui_responsiveness`
**Rileva**: operazioni pesanti che bloccano la UI

Pattern cercati:
- `DispatchQueue.main.sync` dentro codice UI
- `JSONDecoder().decode` su main thread
- `FileManager` operazioni sincrone in view
- `onAppear` con operazioni bloccanti

### 4. `audit_perf_startup`

**MCP**: `coderide_audit_perf_startup`
**Rileva**: problemi di tempo di avvio

Pattern cercati:
- `+load` (Objective-C class load)
- `__attribute__((constructor))` (C constructor)
- Inizializzazione eager di risorse pesanti
- Registrazioni massive in `didFinishLaunching`

### 5. `audit_perf_hot_paths`

**MCP**: `coderide_audit_perf_hot_paths`
**Rileva**: percorsi critici tramite analisi composita

Segnali combinati:
- **Git churn**: file modificati frequentemente (> soglia)
- **Complessità**: loop annidati (O(n²+))
- **Dimensione**: file con molte righe di codice
- Score composito: `churn * 2 + nested_loops * 3 + (lines > 300 ? 1 : 0)`

---

## Architettura

```
┌─────────────────────────────────┐
│   AnalysisToolSelectionPolicy   │ ← Decide quali tool includere
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│   CodeReviewAuditService        │ ← Dispatch: Rust-first, Swift fallback
│   + Support (profili)           │
└────────────┬────────────────────┘
             │
     ┌───────┴───────┐
     ▼               ▼
┌──────────┐   ┌──────────────────────────────────┐
│ Rust     │   │ Swift fallback                    │
│ perf.rs  │   │ CodeReviewAuditService+Perf.swift │
└──────────┘   └──────────────────────────────────┘
```

### Flusso di esecuzione

1. L'utente richiede un'analisi (o viene triggerata automaticamente)
2. `AnalysisToolSelectionPolicy.toolsForPrompt(_:)` analizza il prompt
3. Se la richiesta è generica → include i performance tool
4. `CodeReviewAuditService` invia al dispatch Rust
5. Se Rust fallisce → fallback Swift in `CodeReviewAuditService+Performance.swift`
6. I risultati vengono aggregati come `CodeReviewFinding` con `category: .performance`

### Profili

| Profilo | Tool inclusi |
|---------|-------------|
| `performanceDeep` | Tutti e 5 |
| `iosPreflight` | UI responsiveness, memory, startup |
| `backendRegression` | Bottlenecks |

---

## File del sistema

| File | Righe | Responsabilità |
|------|-------|----------------|
| `Native/RustCore/src/review_audit/performance.rs` | ~280 | Implementazione Rust dei 5 tool |
| `Engine/.../Audit/CodeReviewAuditService+Performance.swift` | ~290 | Fallback Swift dei 5 tool |
| `Engine/.../Audit/AnalysisToolSelectionPolicy.swift` | ~120 | Policy auto-inclusione nei flussi |
| `Engine/.../Audit/CodeReviewAuditModels.swift` | — | Modelli: tool names, profili |
| `Engine/.../Audit/CodeReviewAuditService.swift` | — | Dispatch principale |
| `Engine/.../Audit/CodeReviewAuditService+Support.swift` | — | Profili e configurazione |
| `Engine/.../Tools/Catalog/CoderIDECanonicalToolRegistry+Generated.swift` | — | Registrazione MCP |

---

## Test

### Rust (`Native/RustCore/src/review_audit/mod.rs`)
- `perf_bottlenecks_detects_main_sync` — rileva `DispatchQueue.main.sync`
- `perf_memory_detects_strong_self` — rileva `strong self`
- `perf_hot_paths_scores_churn` — calcola score composito
- `perf_startup_detects_load` — rileva `+load`
- `perf_ui_responsiveness_detects_main_sync` — rileva blocchi UI
- `performance_deep_profile_runs` — verifica profilo completo

### Swift (`Tests/CoderEngineTests/Audit/`)
- `PerformanceAuditTests.swift` — 11 test case per i 5 tool
- `AnalysisToolSelectionPolicyTests.swift` — 10 test case per la policy

---

## Come estendere

### Aggiungere un nuovo pattern a un tool esistente

1. Aggiungere il pattern regex in `performance.rs` (funzione del tool specifico)
2. Aggiungere lo stesso pattern in `CodeReviewAuditService+Performance.swift` (fallback)
3. Aggiungere un test Rust in `mod.rs`
4. Aggiungere un test Swift in `PerformanceAuditTests.swift`

### Aggiungere un nuovo tool performance

1. Aggiungere il `ReviewAuditToolName` in `CodeReviewAuditModels.swift`
2. Implementare la funzione in `performance.rs`
3. Registrare nel dispatch in `dispatch.rs`
4. Aggiungere ai profili in `meta.rs`
5. Implementare il fallback Swift in `CodeReviewAuditService+Performance.swift`
6. Registrare nel dispatch Swift in `CodeReviewAuditService.swift`
7. Aggiungere al tool registry in `CoderIDECanonicalToolRegistry+Generated.swift`
8. Aggiungere test Rust + Swift
9. Aggiornare `AnalysisToolSelectionPolicy` se necessario

---

## Moduli avanzati (Livello 2-3)

### Churn-weighted severity (`perf_churn.rs`)

Integra dati git per pesare la severity dei finding:
- File modificati spesso (>15 commit/90gg) → **High churn**: suggestion→warning, confidence +0.10
- File con churn medio (4-14 commit) → confidence +0.05
- File stabili → nessun boost

Funzioni principali:
- `collect_churn_data()` — raccoglie commit count via `git log`
- `classify_churn()` → High/Medium/Low
- `apply_churn_boost()` — modifica severity e confidence

### Configurable thresholds (`perf_config.rs`)

Carica `.performance-audit.yml` dal workspace root:
```yaml
min_confidence: 0.5
churn_enabled: true
churn_high_commits: 20
include_test_files: false
max_findings_per_file: 10
ignore_patterns:
  - "todo:"
  - ".clone()"
exclude_paths:
  - "vendor/"
severity_overrides:
  "thread.sleep": "critical"
```

### Cross-tool correlation (`perf_correlate.rs`)

**MCP**: `coderide_audit_perf_correlate`

Correla finding performance con bug/concurrency/error handling per identificare **compound issues**:
- Esegue tutti i tool perf + bug concurrency/error/state_machine/nil_crash
- Raggruppa per file, calcola correlation score composito
- File con sia perf che bug finding → severity boosted (1.3x)

### Trending/baseline (`perf_trending.rs`)

**MCP**: `coderide_audit_perf_trending`

Salva risultati in `.performance-audit-baseline.json` e calcola delta:
- **[NEW]** — issue non presente nel baseline precedente
- **[RESOLVED]** — issue presente nel baseline ma non più rilevata
- **[REGRESSION]** — severity peggiorata rispetto al baseline → flaggato critical

### Profili estesi

| Profilo | Tool |
|---------|------|
| `performance_extended` / `performance_full` | Tutti e 7 (5 base + correlate + trending) |

---

## Formato output

Ogni finding viene emesso come `CodeReviewFinding` con:
- `category`: `.performance`
- `severity`: `.medium` (default) o `.high` (per bottleneck critici)
- `file`: percorso del file
- `line`: numero di riga
- `title`: descrizione breve del problema
- `suggestion`: fix consigliato
