# Deep Audit — MCP Tools, Bug Hunter, Code Review, Security Audit & Sub-Agents

**Data:** 2026-03-24
**Scope:** Analisi approfondita di tutto il codice MCP (Rust + Swift) e infrastruttura sub-agent.

## Indice dei bug documentati

### Categoria A — Critici (P0)

| ID | File bug | Titolo | Area |
|----|----------|--------|------|
| A1 | `P0-2026-03-24-rust-chrono-like-to-unix-stub.md` | `chrono_like_to_unix` ritorna sempre 0.0 | Rust MCP / shared_review_state |
| A2 | `P0-2026-03-24-rust-debug-clean-pattern-mismatch.md` | `debug_clean` non matcha i marker di `debug_mark` | Rust MCP / debug_tools |
| A3 | `P0-2026-03-24-rust-uuid-like-collision.md` | `uuid_like` / `generate_id` producono ID non-univoci | Rust MCP / review_tools + debug_tools |
| A4 | `P0-2026-03-24-rust-write-todos-destroys-all.md` | `write_todos` con singolo title distrugge tutti i todo | Rust MCP / shared_state |
| A5 | `P0-2026-03-24-swift-cross-process-lock-fallback-unsafe.md` | Lock timeout fallback perde protezione cross-process | Swift / MCPSharedState+CrossProcessLock |
| A6 | `P0-2026-03-24-swift-todos-no-cross-process-lock.md` | Nessun lock cross-process per todos.json | Swift / MCPSharedState |
| A7 | `P0-2026-03-24-swift-dual-storage-no-transaction.md` | Dual-storage senza consistenza transazionale | Swift / MCPSharedState (pattern trasversale) |
| A8 | `P0-2026-03-24-swift-command-queue-unbounded-growth.md` | Command queue cresce senza limiti | Swift / BugHunterCommands + CodeReviewCommands |
| A9 | `P0-2026-03-24-swift-subagent-limiter-overcounting.md` | SubagentExecutionLimiter supera maxConcurrent | Swift / SubagentExecutionSupport |
| A10 | `P0-2026-03-24-swift-bughunter-timeout-hardcoded-300s.md` | Timeout hardcoded 300s vs 3600s per bugHunter | Swift / SubagentExecutionStream |

### Categoria B — Importanti (P1)

| ID | File bug | Titolo | Area |
|----|----------|--------|------|
| B1 | `P1-2026-03-24-rust-write-results-silently-discarded.md` | Risultati write silenziosamente ignorati | Rust MCP / review_tools |
| B2 | `P1-2026-03-24-rust-no-file-locking-read-modify-write.md` | Nessun file locking su read-modify-write | Rust MCP / shared_review_state + debug_tools |
| B3 | `P1-2026-03-24-rust-collect-debug-files-memory-bomb.md` | `collect_debug_files` legge ogni file nel workspace | Rust MCP / debug_tools |
| B4 | `P1-2026-03-24-rust-no-subprocess-timeout.md` | Nessun timeout sui subprocess | Rust MCP / diagnostics_tools + debug_tools |
| B5 | `P1-2026-03-24-rust-debug-hypothesize-confidence-reset.md` | `debug_hypothesize` update resetta confidence a 50 | Rust MCP / debug_tools |
| B6 | `P1-2026-03-24-rust-debug-hypothesize-root-cause-erased.md` | `debug_hypothesize` update cancella root_cause_type | Rust MCP / debug_tools |
| B7 | `P1-2026-03-24-swift-path-traversal-code-review-session.md` | Path traversal in codeReviewSessionFilePath | Swift / MCPSharedState+CodeReview |
| B8 | `P1-2026-03-24-swift-spin-wait-blocks-main-thread.md` | Spin-wait con Thread.sleep blocca main thread 10s | Swift / MCPSharedState+CrossProcessLock |
| B9 | `P1-2026-03-24-swift-readdata-blocks-after-timeout.md` | readDataToEndOfFile blocca dopo timeout | Swift / SubagentCLIConfig |
| B10 | `P1-2026-03-24-swift-terminate-no-child-kill.md` | terminateProcessIfNeeded non uccide child processes | Swift / SubagentCLIConfig |
| B11 | `P1-2026-03-24-swift-orchestrator-per-task-timeout-wrong.md` | Per-task timeout = jobTimeout / totalTaskCount errato | Swift / OrchestratorMainLoop |
| B12 | `P1-2026-03-24-swift-orchestrator-leaked-lock.md` | Lock acquisition timeout non garantisce rilascio | Swift / OrchestratorMainLoop+Scheduling |
| B13 | `P1-2026-03-24-swift-lock-permissions-inconsistent.md` | Permessi lock file inconsistenti 0o600 vs 0o644 | Swift / MCPSharedState+CrossProcessLock |
| B14 | `P1-2026-03-24-rust-bughunter-status-stub.md` | bughunter_status_payload_from_review sempre None | Rust MCP / review_tools |
| B15 | `P1-2026-03-24-rust-tool-schema-all-string-types.md` | Schema types tutti "string" senza integer/boolean | Rust MCP / tool_schema |
| B16 | `P1-2026-03-24-rust-tool-schema-missing-review-security.md` | Schema mancanti per review/security/bughunter tools | Rust MCP / tool_schema |

### Categoria C — Minori (P2-P3)

| ID | File bug | Titolo | Area |
|----|----------|--------|------|
| C1-C10 | `P2-2026-03-24-minor-issues-batch.md` | Batch di 10 issue minori | Vari |

### Problemi architetturali trasversali

| ID | File | Titolo |
|----|------|--------|
| ARCH-1 | `ARCH-2026-03-24-dual-storage-consistency.md` | Dual-storage senza riconciliazione |
| ARCH-2 | `ARCH-2026-03-24-lock-ordering-undocumented.md` | Lock ordering non documentato |
| ARCH-3 | `ARCH-2026-03-24-timeout-inconsistency.md` | Timeout inconsistenti CLI vs inline |
| ARCH-4 | `ARCH-2026-03-24-id-generation-unsafe.md` | ID generation non-sicura pervasiva |
