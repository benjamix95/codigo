# Bug Pre-esistenti Corretti — 2026-03-25

## Bug 1: MCPSharedBugHunterCommands — `.cancelled` non esiste

### Categoria: B — Importante ma non bloccante
- **Bug**: Riferimento a `MCPSharedBugHunterCommand.Status.cancelled` che non esiste nell'enum
- **Sintomo**: Errore di compilazione — `switch must be exhaustive` / tipo non trovato
- **File**: `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunterCommands.swift:184`
- **Impatto**: Build failure
- **Causa**: L'enum `Status` definisce solo `.pending`, `.processing`, `.completed`, `.failed` — nessun `.cancelled`
- **Fix**: Rimosso `|| cmd.status == .cancelled` dalla condizione `isTerminal`
- **Scope**: 1 riga, 1 file

---

## Bug 2: shared_review_state.rs — Result type mismatch in write_json

### Categoria: B — Importante ma non bloccante
- **Bug**: `Ok(inner) => inner` dove `inner` è `()` ma il match deve produrre `Result<(), String>`
- **Sintomo**: Errore di compilazione — `expected Result<(), String>, found ()`
- **File**: `Native/CoderideMCPServerRust/src/shared_review_state.rs:221`
- **Impatto**: Build failure dell'intero crate `coderide_mcp_server_rust`
- **Causa**: `with_file_lock` ritorna `Result<T, String>` dove `T = ()` dal body closure. Il match `Ok(inner)` dà `inner: ()` che deve essere re-wrappato
- **Fix**: `Ok(inner) => Ok(inner)` e `Err(e) => Err(e)`
- **Scope**: 2 righe, 1 file

---

## Bug 3: UnifiedToolRuntime+IndexSemantic — switch non exhaustive

### Categoria: C — Conseguenza del nuovo `.vectorIndex` case
- **Bug**: Due switch su `HybridSearchSource` non gestivano il nuovo case `.vectorIndex`
- **Sintomo**: Errore di compilazione — `switch must be exhaustive`
- **File**: `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Index/Search/Semantic/UnifiedToolRuntime+IndexSemantic.swift:106,117`
- **Impatto**: Build failure
- **Fix**: Aggiunto `case .vectorIndex: return "vector_index"` e `case .vectorIndex: return "vector index"`
- **Scope**: 2 case aggiunti, 1 file
