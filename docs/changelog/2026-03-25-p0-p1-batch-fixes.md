# Changelog — 2026-03-25 — P0/P1 Batch Fixes (Rust + Swift)

## Rust MCP Server

### R-P0-2: plan_state TOCTOU race — file lock cross-processo
- **File**: `plan_state.rs`
- `create_snapshot()` e `mutate_latest_snapshot()` ora wrappati in `with_file_lock(Exclusive)`
- `write_document()` usa atomic write (temp + rename)

### R-P1-1: edit_tools atomic write
- **File**: `edit_tools.rs`
- Nuova `atomic_write()` helper — tutti i 4 `fs::write()` ora usano temp+rename
- Previene corruzioni file sorgente su interruzione

### R-P1-2: shared_review_state atomic write
- **File**: `shared_review_state.rs`
- `write_json()` ora usa atomic write (temp + rename)

### R-P2-3: tool_schema required fields
- **File**: `tool_schema.rs`
- `coderide_debug_test_check`: aggiunto `"scope"` come campo required

## Swift

### S-P0-1: SubagentExecutionLimiter overcounting
- **File**: `SubagentExecutionSupport.swift`
- `release()` non decrementa più `running` quando trasferisce slot a un waiter
- `acquire()` non incrementa più `running` dopo resume da waiter (slot già trasferito)
- Previene overcounting: max N subagent concorrenti rispettato

### S-P1-7: Lock permissions inconsistenti
- **File**: `MCPSharedState+CrossProcessLock.swift`
- CodeReview lock: da `S_IRUSR | S_IWUSR` (0o600) a `0o644`
- Uniformato con BugHunter lock per cross-process compatibility

### ChatRenderLogger Swift 6 thread safety (pre-existing build fix)
- **File**: `ChatRenderLogger.swift`, `ChatPanelView+RootLayout.swift`, `ChatPanelView+PartC_MessageHeader.swift`, `ChatTurnTimelineInterleaver.swift`
- Rimosso `@MainActor` da `ChatRenderLogger`, ora nonisolated thread-safe
- Aggiunto `os_unfair_lock` per proteggere throttle map
- `nonisolated(unsafe)` per static mutable state (prep Swift 6)
- Rimossi `let _ = logRender()` che bloccavano ViewBuilder type inference
