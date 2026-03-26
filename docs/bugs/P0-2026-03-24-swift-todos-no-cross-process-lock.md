# P0 — Nessun lock cross-process per todos.json

## Bug Fix Record
- Categoria: A - Critico
- Bug: `MCPSharedState` usa solo un `DispatchQueue` intra-processo per serializzare accessi a `todos.json`, ma il server MCP Rust (processo separato) legge/scrive lo stesso file senza coordinamento.
- Sintomo: Scritture concorrenti da Swift app e Rust MCP server possono corrompere `todos.json` o causare perdita di todo.
- Impatto: Perdita silenziosa di todo, stato inconsistente tra app e MCP server.
- Gravità: P0
- Steps to reproduce:
  1. Dalla UI dell'app Swift, aggiungere un todo.
  2. Contemporaneamente, dal tool MCP `coderide_todo`, aggiungere un altro todo.
  3. Verificare il contenuto di `todos.json` — uno dei due todo potrebbe mancare.
- Risultato attuale: `readTodos` e `writeTodos` in `MCPSharedState.swift` usano `fileAccessQueue.sync { ... }` — serializzazione solo intra-processo. Nessun `flock()` o advisory lock.
- Risultato atteso: Le operazioni su `todos.json` devono essere protette da un advisory file lock cross-processo, come già fatto per code review e bug hunter.
- Causa probabile: I todo sono stati implementati prima dell'infrastruttura di advisory locking. Quando il locking è stato aggiunto per review/bughunter, i todo non sono stati aggiornati.
- Scope consentito: `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState.swift` — `readTodos`, `writeTodos`, `upsertTodoFromMCP`.
- Non-scope: Rust MCP server todo handling, UI todo, persistence bridge.
- Moduli confinanti da verificare: `shared_state.rs` (Rust), `MCPSharedState+PersistenceBridge.swift`.
- Test da aggiungere o aggiornare:
  - Test: due write concorrenti da thread diversi → nessuna perdita dati.
  - Test: read durante write → dati consistenti.
- Strategia di fix minimo: Aggiungere un advisory file lock per `todos.json` seguendo lo stesso pattern di `withBugHunterFileLock` / `withCodeReviewFileLock`. Creare `withTodosFileLock` e usarlo in `readTodos` / `writeTodos`.
- Verifica post-fix:
  1. Test concorrenza con accessi simultanei.
  2. Build + test suite.
  3. Smoke test: aggiungere todo da UI e da MCP tool contemporaneamente.
- Commit previsto: `fix(mcp-shared-state): add cross-process advisory lock for todos`
