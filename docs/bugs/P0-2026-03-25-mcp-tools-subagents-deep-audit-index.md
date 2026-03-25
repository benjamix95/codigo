# P0 — Deep Audit MCP Tools, Sub-Agents, Code Review, Bug Hunter — 2026-03-25

## Sommario
Analisi approfondita di tutti i tool MCP (Rust + Swift), sub-agent, pipeline code review e bug hunter.
Trovati **30 bug** totali: 11 P0, 12 P1, 7 P2.

---

## P0 — CRITICI (11)

### RUST MCP SERVER

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| R-P0-1 | write_todos TOCTOU race — read-modify-write senza file lock | shared_state.rs | 104-106 | Race Condition |
| R-P0-2 | plan_state TOCTOU race — create_snapshot/mutate senza lock | plan_state.rs | 50,74,439-453 | Race Condition |
| R-P0-3 | debug_tools write_store errori ignorati (`let _ = write_store()`) in 10+ call sites | debug_tools.rs | 132,174,200,271,298,311,401,456,530,736 | Error Handling |
| R-P0-4 | shell_text() subprocess senza timeout se gtimeout non disponibile | diagnostics_tools.rs | 82 | Hang Risk |

### SWIFT SUB-AGENTS

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| S-P0-1 | SubagentExecutionLimiter overcounting — release() decrementa prima che waiter incrementi | SubagentExecutionSupport.swift | 32-51 | Concurrency |
| S-P0-2 | SubagentEventRecorder array 10K eventi senza time-window eviction — OOM su job lunghi | SubagentExecutionLiveState.swift | 73-89 | Memory |
| S-P0-3 | MCPSharedState todos.json senza cross-process lock — race con Rust MCP server | MCPSharedState.swift | - | Race Condition |
| S-P0-4 | MCPSharedState dual-storage (Postgres + JSON) senza transazione atomica | MCPSharedState.swift | - | Data Consistency |

### SWIFT MCP / CODE REVIEW

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| S-P0-5 | readData blocca indefinitamente in MCPLifecycleRustBackend.readLine() | MCPLifecycleRustBackend.swift | 267 | Blocking I/O |
| S-P0-6 | readDataToEndOfFile blocca dopo git diff in CodeReview scope calc | CodeReviewMultiSwarmProvider+Scope.swift | 149-150 | Blocking I/O |
| S-P0-7 | Tool schema String opaco — perde type info (tutto diventa String) | MCPLifecycleRustModels.swift | 57 | Type Unsafety |

---

## P1 — IMPORTANTI (12)

### RUST MCP SERVER

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| R-P1-1 | edit_tools fs::write non atomic (no temp+rename) | edit_tools.rs | 39,64,109,153 | Data Loss |
| R-P1-2 | shared_review_state fs::write non atomic | shared_review_state.rs | 213 | Data Loss |
| R-P1-3 | xcodebuild path hardcoded, no validation | debug_tools.rs | 1261 | Silent Failure |

### SWIFT SUB-AGENTS

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| S-P1-1 | Cross-process lock fallback a NSRecursiveLock senza warning | MCPSharedState+CrossProcessLock.swift | 76,130-134 | Race Condition |
| S-P1-2 | Spin-wait blocca thread fino a 10s su lock acquisition | MCPSharedState+CrossProcessLock.swift | 94-138 | UI Freeze |
| S-P1-3 | Command queue cresce indefinitamente — no pruning | MCPSharedState+BugHunterCommands.swift, +CodeReviewCommands.swift | - | Memory |
| S-P1-4 | readDataToEndOfFile blocca indefinitamente dopo timeout CLI | SubagentCLIConfig.swift | 173-177,186-191 | Thread Leak |
| S-P1-5 | terminateProcessIfNeeded non uccide child processes | SubagentCLIConfig.swift | 259-272 | Resource Leak |
| S-P1-6 | Per-task timeout inversione: max(jobTimeout/tasks, 30s) supera job timeout | OrchestratorMainLoop | - | Timeout Logic |
| S-P1-7 | Lock permissions inconsistenti: 0o600 vs 0o644 | MCPSharedState+CrossProcessLock.swift | 14-15,33 | Permission |
| S-P1-8 | Lock leak su exception in ReviewPipeline FixStage | ReviewPipelineCoordinator+FixStage.swift | 38-47 | Resource Leak |
| S-P1-9 | Stale BugHunter command timeout 3605s inconsistente | MCPSharedState+BugHunterCommands.swift | 7 | Timeout |

---

## P2 — MINORI (7)

| ID | Bug | File | Righe | Tipo |
|----|-----|------|-------|------|
| R-P2-1 | regex_escape inefficiente + regex_chars inutile | search_tools.rs | 284-298 | Performance |
| R-P2-2 | web timeout validation manca upper bound | web_tools.rs | 135 | Timeout |
| R-P2-3 | tool_schema coderide_debug_test_check — required vuoto | tool_schema.rs | 117 | Schema |
| S-P2-1 | Output truncation silente 120 chars senza evento | SubagentExecutionLiveState.swift | 128 | UX |
| S-P2-2 | SubagentTimeoutError messaggio hardcoded "5 minuti" | SubagentExecutionSupport.swift | 3-8 | UX |
| S-P2-3 | FileLock polling loop CPU-intensive | CodeReviewSessionState.swift | 33-54 | Performance |
| S-P2-4 | Process.terminate() no SIGKILL/process group kill | MCPTransportFactory.swift | 111-121 | Resource Leak |

---

## PROBLEMI ARCHITETTURALI

| ID | Problema | Impatto |
|----|----------|---------|
| ARCH-1 | Dual-storage (Postgres + JSON) senza consistency guarantee | Ghost sessions, dati stale |
| ARCH-2 | Timeout definiti in 5+ posti diversi senza coordinamento | Comportamento imprevedibile |
| ARCH-3 | Nessun file locking uniforme cross-process | Race condition sistematica |

---

## ORDINE DI FIX CONSIGLIATO

1. **S-P0-1**: SubagentLimiter overcounting (già fixato in sessione precedente)
2. **R-P0-1**: write_todos file lock
3. **R-P0-4**: subprocess timeout fallback
4. **S-P0-5**: readData blocking I/O
5. **R-P0-3**: debug_tools error handling
6. **S-P1-3**: command queue pruning
7. **S-P1-5**: process group termination
8. **Batch P1**: tutti i restanti P1
9. **Batch P2**: tutti i P2
