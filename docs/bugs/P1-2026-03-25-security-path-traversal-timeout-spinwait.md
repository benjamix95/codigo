# P1 — Security, timeout e spin-wait fixes — 2026-03-25

## Bug fixati in questo batch

### P1-Rust-1: Path traversal in edit_tools.rs
- **File**: `edit_tools.rs` riga 208
- **Bug**: `workspace.canonicalize().unwrap_or(workspace.to_path_buf())` — se canonicalize fallisce, il path non canonicalizzato permette traversal con `../..`
- **Impatto**: potenziale scrittura di file fuori dal workspace
- **Fix**: se canonicalize fallisce, rifiutare il path con return `PathBuf::new()`

### P1-Rust-2: web_tools.rs float timeout diventa 0
- **File**: `web_tools.rs` riga 133
- **Bug**: `as_i64()` fallisce su JSON float (e.g. `30.5`), poi `as_str()` fallisce su numeri → default
- **Impatto**: timeout non rispettato, usa default invece del valore specificato
- **Fix**: aggiunto `as_f64().map(|f| f as i64)` come fallback intermedio

### P1-Swift-3: Spin-wait main thread warning
- **File**: `MCPSharedState+CrossProcessLock.swift` in `acquireAdvisoryFileLock`
- **Bug**: `Thread.sleep(0.05)` in loop può bloccare il main thread fino a 30s
- **Impatto**: UI freeze percepita come crash dall'utente
- **Fix**: aggiunto `#if DEBUG` warning log quando chiamato dal main thread
