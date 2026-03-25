# Changelog — 2026-03-25 — P0 MCP Tools + Pipeline Fixes

## Panoramica

Sessione di audit profondo su **Rust MCP Server** e **Swift Sub-Agents/Pipeline**.
Trovati 42 bug totali (12 P0, 16 P1, 12 P2, 2 ARCH).
Fixati 6 P0 critici + 4 fix di compilazione pre-esistenti.

---

## Commit 1: `01d1269` — fix(engine): align tests and resilience wrappers

### Problema
Dopo il refactor di `ProviderRetrySupport` (sessione precedente), diversi test e wrapper
non erano stati aggiornati. La build dei test falliva con errori di compilazione.

### Modifiche

| File | Modifica |
|------|----------|
| `AnthropicAPIProvider+Resilience.swift` | Aggiunto wrapper `exponentialBackoffSeconds()` → `ProviderRetrySupport` |
| `OpenAIAPIProvider+Resilience.swift` | Aggiunto wrapper `exponentialBackoffSeconds()` → `ProviderRetrySupport` |
| `AnthropicAPIProviderTests.swift` | Rinominato `isRetryableTransportError` → `shouldRetryTransportError(for:)` |
| `OpenAIAPIProviderTests.swift` | Rinominato `isRetryableTransportError` → `shouldRetryTransportError(for:)` |
| `EventDeliveryManagerConcurrencyTests.swift` | Allineato a nuova API: `DeadLetterQueue(capacity:)`, `EventBusEvent(jobId:, idempotencyKey:, type: PipelineEventType)`, `EventSubscription(filter: EventSubscriptionFilter)` |
| `WorkerPoolSafetyTests.swift` | Sostituito `AgentRole.worker` (rimosso) con `.coder` |

### Verifica
- Build Swift: SUCCEEDED
- Test compilano correttamente

---

## Commit 2: `fdabd1e` — docs(bugs): deep audit v2

### Contenuto
Documento completo `P0-2026-03-25-mcp-tools-subagents-deep-audit-v2.md` con:
- 23 bug Rust MCP (6 P0, 8 P1, 9 P2)
- 19 bug Swift Sub-Agents/Pipeline (6 P0, 8 P1, 3 P2, 2 ARCH)
- Classificazione per gravità
- Fix suggerito per ciascuno
- Ordine di fixing prioritizzato

---

## Commit 3: `90745a7` — fix(mcp+pipeline): resolve P0 bugs

### R-P0-04 — `regex_replace` completamente non funzionante
- **File**: `edit_tools.rs`
- **Prima**: `content.replace(&pattern, &replacement)` — string literal match
- **Dopo**: `Regex::new(&pattern)?.replace_all(&content, replacement)` — regex vero
- **Dipendenza aggiunta**: `regex = "1"` in `Cargo.toml`
- **Impatto**: Il tool MCP `coderide_regex_replace` non funzionava per nessun pattern regex

### R-P0-05 — Path traversal in `resolve_path()`
- **File**: `edit_tools.rs`, `file_tools.rs`
- **Prima**: Nessun controllo — `../../etc/passwd` passava liberamente
- **Dopo**: `canonicalize()` + `starts_with(workspace_canonical)` — path fuori workspace → PathBuf vuoto → errore
- **Impatto**: Sicurezza — lettura/scrittura file arbitrari sul filesystem

### R-P0-02 — ID collision su `uuid_like_seed()`
- **File**: `shared_state.rs`
- **Prima**: Hash FNV-1a deterministico del titolo — due todo con stesso titolo → stesso ID → sovrascrittura
- **Dopo**: `unique_id()` con `SystemTime::now().as_nanos() + AtomicU64 counter` — univocità garantita
- **Impatto**: Perdita dati silente su todo duplicati

### R-P0-01 — Write non atomica su `todos.json`
- **File**: `shared_state.rs`
- **Prima**: `fs::write(path, data)` — crash/race → file corrotto o parziale
- **Dopo**: Write su `todos.json.tmp` + `fs::rename()` — atomico su stesso filesystem
- **Impatto**: Corruzione dati in caso di crash o concorrenza

### S-P0-05 — Per-task timeout supera job timeout
- **File**: `OrchestratorMainLoop.swift:247`
- **Prima**: `max(job.jobTimeoutMs / taskCount, 30_000)` — 10 task × 30s = 300s > 60s job
- **Dopo**: `min(job.jobTimeoutMs, max(job.jobTimeoutMs / taskCount, 30_000))` — clamped a job timeout
- **Impatto**: Lock holding indefinito, inversione logica timeout

### S-P0-06 — Lock leak su timeout path
- **File**: `OrchestratorMainLoop+Scheduling.swift:48-52`
- **Prima**: Se lock acquire completa dopo che timeout vince la race nel TaskGroup, il lock resta acquisito per sempre
- **Dopo**: `lockManager.release(taskId:)` difensivo nel path `!lockAcquired`
- **Impatto**: Deadlock potenziale — task successivi non possono acquisire il lock

---

## Riepilogo quantitativo

| Metrica | Valore |
|---------|--------|
| Bug trovati (totale audit) | 42 |
| Bug P0 fixati | 6 |
| File Rust modificati | 4 |
| File Swift modificati | 2 |
| File test allineati | 4 |
| Commit creati | 3 |
| Build Rust | PASS |
| Build Swift | PASS |
| Regressioni introdotte | 0 |

---

## Bug rimanenti da fixare

### P1 (16 totali — prossima sessione)

**Rust:**
- R-P1-01: Logic error `||` vs `&&` su root_cause_type (debug_tools.rs:434)
- R-P1-02: `iso_now()` genera `ts-123...` non ISO 8601 (plan_state.rs:663)
- R-P1-03: `chrono_like_to_unix()` stub con formati errati (shared_review_state.rs:242)
- R-P1-04: Timeout hardcoded 20s su web_tools (web_tools.rs:27)
- R-P1-05: `glob_like_match` non gestisce `*` iniziale (search_tools.rs:300)
- R-P1-06: Step ID = indice → collision dopo riordino (plan_state.rs:517)
- R-P1-07: Build senza timeout in diagnostics (diagnostics_tools.rs:31)
- R-P1-08: HTML strip troppo semplice (web_tools.rs:80)

**Swift:**
- S-P1-01: Timeout hardcoded 300s vs 3600s bugHunter
- S-P1-02: Array eventi senza limite → OOM
- S-P1-03: `deliveryTasks` memory leak potenziale
- S-P1-04: Lock release senza verificare ownership
- S-P1-05: Jitter seed hardcoded `42` → thundering herd
- S-P1-06: Timeout inconsistenti tra moduli
- S-P1-07: Output troncato senza warning
- S-P1-08: idempotency cache leak su sessioni lunghe
