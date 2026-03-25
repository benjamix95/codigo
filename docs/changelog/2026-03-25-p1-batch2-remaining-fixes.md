# Changelog — 2026-03-25 — P1 Batch 2 (Remaining)

## Panoramica

Secondo batch P1: timeout, HTML entities, step ID, diagnostics timeout, output truncation warning.

---

## Fix Rust

### R-P1-04 — Timeout web_tools parametrizzabile + exit code 28
- **File**: `web_tools.rs`
- **Prima**: Timeout hardcoded 20s, nessun feedback su timeout, exit code ignorato
- **Dopo**: Default 30s, parametro `timeout` (1-120s), exit code 28 = messaggio "timed out", feedback chiaro
- **Impatto**: Richieste web lunghe ora hanno timeout configurabile e feedback utile

### R-P1-06 — Step ID collision dopo riordino
- **File**: `plan_state.rs:517`
- **Prima**: ID = indice (`1`, `2`, `3`...) — collision dopo step_reorder
- **Dopo**: `next_id("step")` genera ID univoci timestamp-based
- **Impatto**: Plan step non si perdono piu' durante riordino

### R-P1-07 — Diagnostics/build senza timeout
- **File**: `diagnostics_tools.rs`
- **Prima**: `Command::new().output()` senza timeout — build poteva bloccare indefinitamente
- **Dopo**: Wrapper con `timeout`/`gtimeout` (120s), exit code 124 = messaggio timeout
- **Impatto**: Tool diagnostics non blocca piu' il server MCP

### R-P1-08 — HTML entity decoding incompleto
- **File**: `web_tools.rs`
- **Prima**: Solo `&amp;`, `&quot;`, `&#39;`
- **Dopo**: Aggiunto `&lt;`, `&gt;`, `&apos;`, `&nbsp;`
- **Impatto**: Risultati ricerca web piu' puliti

## Fix Swift

### S-P1-07 — Output troncato senza warning
- **File**: `ToolEnabledLLMProvider+SubagentExecutionStream.swift:216`
- **Prima**: `String(joined.prefix(limit))` silente
- **Dopo**: Log via `SubagentPipelineLogger` quando output supera il limite
- **Impatto**: Visibilita' su quando e quanto l'output subagent viene troncato

---

## Riepilogo

| Metrica | Valore |
|---------|--------|
| P1 fixati | 5 |
| File Rust modificati | 3 |
| File Swift modificati | 1 |
| Build Rust | PASS |
| Build Swift | PASS |
| Regressioni introdotte | 0 |

## P1 rimanenti (basso impatto / architetturali)

- S-P1-01: Timeout 300s vs 3600s bugHunter (richiede analisi config cross-module)
- S-P1-03: deliveryTasks memory leak potenziale (basso rischio, defer gia' presente)
- S-P1-06: Timeout inconsistenti tra moduli (architetturale, richiede refactor centralizzato)
- S-P1-08: idempotency cache leak su sessioni lunghe (minore, pruning gia' presente)
