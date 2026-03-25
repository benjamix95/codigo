# P0/P1 — Deep audit MCP tools, sub-agents, bug hunter — 2026-03-25

## Panoramica
Audit approfondito di tutti i tool MCP (Rust + Swift), sub-agent, bug hunter,
code review e security audit. Trovati e fixati bug critici in entrambi i layer.

---

## Bug fixati in questo batch

### P0-Rust-1: Silent error discard in review_tools.rs
- **File**: `review_tools.rs` righe 75, 117, 147, 182
- **Bug**: `let _ = state::write_*_commands(...)` scartava silenziosamente errori di persistenza
- **Impatto**: comandi review/bughunter/security persi senza traccia, pipeline rotta
- **Fix**: check esplicito con `if let Err(e)` + return `CallToolResult::error`

### P0-Rust-2: uuid_like() collision risk
- **File**: `review_tools.rs` riga 783
- **Bug**: ID generato da `f64.to_bits()` → solo ~16 hex digits, collisioni in range microsecondo
- **Impatto**: sessioni review/bughunter con ID duplicati → sovrascrittura dati
- **Fix**: nanosecond timestamp + AtomicU64 sequence counter → `{:016x}-{:04x}`

### P0-Rust-3: file_lock.rs timeout troppo corto (10s → 30s)
- **File**: `file_lock.rs` riga 56
- **Bug**: timeout hardcoded 10s, insufficiente sotto contention alta
- **Impatto**: timeout spurii → fallback senza cross-process protection → data corruption
- **Fix**: aumentato a 30s, aggiornato messaggio errore

### P0-Swift-4: MCPSharedState todos senza cross-process lock
- **File**: `MCPSharedState.swift` — `readTodos()`, `writeTodos()`, `upsertTodoFromMCP()`, `batchWriteTodosFromMCP()`
- **Bug**: solo `DispatchQueue` intra-processo, nessun advisory file lock cross-processo
- **Impatto**: Rust MCP server e Swift app scrivono `todos.json` in parallelo → data loss
- **Fix**: aggiunto `withTodosAdvisoryLock` attorno a tutte le operazioni todo

### P0-Swift-5: Lock file permissions 0o644 → 0o600
- **File**: `MCPSharedState+CrossProcessLock.swift`
- **Bug**: lock files creati con 0o644 (world-readable) invece di 0o600
- **Impatto**: information disclosure — altri utenti possono ispezionare operazioni di lock
- **Fix**: cambiato `createMode` da 0o644 a 0o600 per tutti i lock (todos, review, bughunter)

### P0-Swift-6: Cross-process lock fallback senza log in release
- **File**: `MCPSharedState+CrossProcessLock.swift` riga 148
- **Bug**: log di fallback solo in `#if DEBUG`, invisibile in release
- **Impatto**: data corruption silenziosa in produzione quando il lock va in timeout
- **Fix**: NSLog sempre attivo con messaggio WARNING esplicito

### P1-Rust-7: debug_tools write_lines error silenzioso
- **File**: `debug_tools.rs` riga 875
- **Bug**: `let _ = write_lines(&file, &kept)` scartava errore
- **Impatto**: file di debug non puliti correttamente, marker rimangono nel codice
- **Fix**: log esplicito con `eprintln!` in caso di errore

---

## Bug trovati ma già fixati in sessioni precedenti

- P0: SubagentExecutionStream hardcoded 300s timeout → ora usa `SubagentCLIConfig.timeout(for: role)` con 3600s per bugHunter
- P0: SubagentExecutionLimiter overcounting → slot transfer senza decrement/increment gap

---

## Bug documentati ma non ancora fixati (backlog)

### P1-Rust: path traversal in edit_tools.rs (canonicalize fallback)
### P1-Rust: plan_state.rs JSON parse `.ok()?` nasconde errori
### P1-Rust: web_tools.rs float timeout silenziosamente diventa 0
### P1-Swift: spin-wait su main thread in acquireAdvisoryFileLock
### P1-Swift: process termination senza cleanup child processes
### P0-Arch: dual-storage PostgreSQL+JSON senza transactional consistency
### P2: schema types tutti "string", spin-wait loop inefficiente, dead code
