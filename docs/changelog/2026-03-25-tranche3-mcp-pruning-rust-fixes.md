# Changelog — 2026-03-25 — Tranche 3: MCP command pruning + Rust fixes

## Fix applicati

### 1. P0 — Command queue pruning (BugHunter + CodeReview)
- **File**: `MCPSharedState+BugHunterCommands.swift`, `MCPSharedState+CodeReviewCommands.swift`
- **Problema**: code di comandi crescono indefinitamente, nessun pruning
- **Fix**: aggiunto pruning automatico — comandi terminali > 24h rimossi, cap a 200 totali

### 2. P1 — `finding_map` message field non inserito nella map
- **File**: `review_tools.rs`
- **Problema**: campo `message` estratto dal JSON ma scartato con `let _ = message`
- **Fix**: `let _ = message` → `map.insert("message".to_string(), message)`

### 3. P1 — `write_json` senza advisory file lock
- **File**: `shared_review_state.rs`
- **Problema**: write atomica (temp+rename) ma senza lock — race condition cross-process
- **Fix**: wrappato con `with_file_lock(path, LockMode::Exclusive, || { ... })`

### 4. P0 — `ffi::common` modulo privato blocca build
- **File**: `RustCore/src/ffi/mod.rs`
- **Problema**: `mod common` privato, ma `trigram/ffi.rs` lo usa da altro modulo
- **Fix**: `mod common` → `pub(crate) mod common`

## Verifiche
- Rust: `cargo check -p coderide_mcp_server_rust` — OK (solo warning)
- Swift: `xcodebuild build -scheme "Solo Code-Debug"` — BUILD SUCCEEDED
