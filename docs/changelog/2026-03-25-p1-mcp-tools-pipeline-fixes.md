# Changelog — 2026-03-25 — P1 MCP Tools + Pipeline Fixes

## Panoramica

Fix batch P1 per Rust MCP Server e Swift Pipeline.
Fixati 5 P1 + 1 fix compilazione pre-esistente.

---

## Fix P1 Rust

### R-P1-01 — Logic error `||` vs `&&` su root_cause_type
- **File**: `debug_tools.rs:434`
- **Prima**: `if !existing.root_cause_type.is_empty() || !string_arg(arguments, "root_cause_type").is_empty()` — sovrascriveva con stringa vuota se il vecchio valore era non-vuoto
- **Dopo**: `if !string_arg(arguments, "root_cause_type").is_empty()` — aggiorna solo se il nuovo valore non e' vuoto
- **Impatto**: root_cause_type si cancellava accidentalmente durante update di ipotesi

### R-P1-02 — `iso_now()` generava `ts-123...` non ISO 8601
- **File**: `plan_state.rs:662-663`
- **Prima**: `iso_now()` chiamava `next_id("ts")` che generava `ts-<nanos>`
- **Dopo**: `chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()` — ISO 8601 valido
- **Impatto**: Tutti i timestamp dei plan snapshot erano non-parsabili da `chrono_like_to_unix()`

### R-P1-03 — `chrono_like_to_unix()` parsing fragile
- **File**: `shared_review_state.rs:242-272`
- **Prima**: 8 formati con `%:z` e `%z` (problematici in chrono Rust), nessun RFC 3339
- **Dopo**: Fast path con `DateTime::parse_from_rfc3339()` + fallback su formati naive (assume UTC)
- **Impatto**: Timestamp parsing falliva su stringhe ISO 8601 standard

### R-P1-05 — `glob_like_match` non gestiva `*` iniziale/finale
- **File**: `search_tools.rs:300-319`
- **Prima**: `*.rs` matchava qualsiasi stringa contenente "rs" ovunque
- **Dopo**: Rispetta prefix/suffix anchoring — `*.rs` matcha solo stringhe che finiscono con `.rs`, `src/*` matcha solo stringhe che iniziano con `src/`
- **Impatto**: Ricerche file con pattern glob davano risultati errati

## Fix P1 Swift

### S-P1-02 — SubagentEventRecorder senza limite eventi
- **File**: `SubagentExecutionLiveState.swift:73-83`
- **Prima**: Array `events` cresceva senza limiti — OOM su loop di output
- **Dopo**: Cap a 10.000 eventi con FIFO eviction
- **Impatto**: Crash per Out of Memory su subagent con output prolisso

### S-P1-05 — Jitter seed hardcoded `42`
- **File**: `TaskCompletionHandler.swift:44`
- **Prima**: `jitterSeed: UInt64 = 42` — tutti i job usano stesso pattern di jitter
- **Dopo**: `UInt64(Date().timeIntervalSince1970.bitPattern &>> 16)` — seed basato su timestamp
- **Impatto**: Thundering herd su retry — tutti i job retryano simultaneamente

## Fix compilazione pre-esistente

### ChatPanelView+PartC — scrollState orfano
- **File**: `ChatPanelView+PartC_MessageHeader.swift:292-294`
- **Prima**: Riferimento a `scrollState.autoScrollWorkItem` su tipo che non ha quel membro (codice orfano da refactor precedente)
- **Dopo**: `.onDisappear { }` vuoto
- **Impatto**: BUILD FAILED su intero progetto

---

## Riepilogo

| Metrica | Valore |
|---------|--------|
| P1 fixati | 5 |
| Fix compilazione | 1 |
| File Rust modificati | 4 |
| File Swift modificati | 3 |
| Build Rust | PASS |
| Build Swift | PASS |
| Regressioni introdotte | 0 |

## P1 rimanenti

- S-P1-01: Timeout hardcoded 300s vs 3600s bugHunter (richiede analisi configurazione)
- S-P1-03: deliveryTasks memory leak potenziale (basso rischio)
- S-P1-06: Timeout inconsistenti tra moduli (architetturale)
- S-P1-07: Output troncato senza warning (minore)
- S-P1-08: idempotency cache leak su sessioni lunghe (minore)
- R-P1-04: Timeout hardcoded 20s web_tools (minore)
- R-P1-06: Step ID collision plan_state (minore)
- R-P1-07: Build senza timeout diagnostics (minore)
- R-P1-08: HTML strip troppo semplice (minore)
