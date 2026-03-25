# Changelog — 2026-03-25 — P0 Rust MCP Server Fixes

## Fix applicati

### 1. R-P0-1: write_todos TOCTOU race — file lock cross-processo
- **File**: `shared_state.rs`, nuovo `file_lock.rs`
- **Problema**: `write_todos()` faceva read-modify-write senza lock — race condition con Swift app che scrive sullo stesso `todos.json`
- **Fix**:
  - Creato modulo `file_lock` con advisory flock (LOCK_EX/LOCK_SH) + timeout 10s + fallback non-Unix
  - `write_todos()` ora wrappa read+push+write dentro `with_file_lock(Exclusive)`
  - Aggiunta dipendenza `libc` per flock syscall
- **Test**: cargo check + build release pass

### 2. R-P0-3: debug_tools write_store errori ignorati silenziosamente
- **File**: `debug_tools.rs`
- **Problema**: 10 call site usavano `let _ = write_store(&store)` ignorando l'errore — perdita dati silenziosa
- **Fix**:
  - `write_store()` ora usa atomic write (temp file + rename) per prevenire corruzioni
  - Creata `persist_store()` wrapper che logga errori su stderr invece di silenziarli
  - Sostituiti tutti i 10 `let _ = write_store()` con `persist_store()`
- **Test**: cargo check + build release pass

### 3. R-P0-4: subprocess senza timeout fallback
- **File**: `diagnostics_tools.rs`
- **Problema**: se `timeout`/`gtimeout` non sono disponibili su macOS, `Command::new(command).output()` non ha timeout — hang infinito possibile
- **Fix**:
  - Implementato `run_with_native_timeout()` che usa `child.try_wait()` + polling loop con kill dopo N secondi
  - Timeout 120s come il path con `gtimeout`
  - Kill + exit code 124 sintetico (compatibile con coreutils convention)
- **Test**: cargo check + build release pass
