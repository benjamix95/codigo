# Changelog — 2026-03-25 — P0/P1 MCP tools, sub-agents, bug hunter audit fixes

## Contesto
Audit approfondito di tutti i tool MCP Rust, sub-agents Swift, bug hunter e code review.
Trovati ~30 bug totali (P0/P1/P2). Fixati tutti i P0 e i P1 critici in questo batch.

## Fix Rust MCP Server

### review_tools.rs — Error handling per write commands
- 4 occorrenze di `let _ = state::write_*_commands(...)` sostituite con error check + return error
- Comandi review, security e bughunter ora propagano errori di persistenza al chiamante

### review_tools.rs — UUID generation collision-safe
- `uuid_like()` riscritto: da `f64.to_bits()` a nanosecond timestamp + AtomicU64 counter
- Formato: `{:016x}-{:04x}` — collision-free anche in burst rapidi

### file_lock.rs — Timeout aumentato 10s → 30s
- Riduce timeout spurii sotto contention alta

### debug_tools.rs — write_lines error logging
- `let _ = write_lines(...)` sostituito con log esplicito `eprintln!`

## Fix Swift (CoderEngine)

### MCPSharedState — Cross-process lock per todos
- Aggiunto `withTodosAdvisoryLock` su `readTodos()`, `writeTodos()`, `upsertTodoFromMCP()`, `batchWriteTodosFromMCP()`
- Nuovo `todosFallbackLock` NSRecursiveLock per intra-processo

### MCPSharedState+CrossProcessLock — Lock permissions fix
- `createMode` cambiato da 0o644 a 0o600 per todos, code review e bug hunter lock files
- Log di fallback ora sempre attivo (rimosso `#if DEBUG`)

## File toccati
- `Native/CoderideMCPServerRust/src/review_tools.rs`
- `Native/CoderideMCPServerRust/src/file_lock.rs`
- `Native/CoderideMCPServerRust/src/debug_tools.rs`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
