# P1 — Spin-wait con Thread.sleep può bloccare il main thread per 10 secondi

## Bug Fix Record
- Categoria: B - Importante
- Bug: `acquireAdvisoryFileLock` in `MCPSharedState+CrossProcessLock.swift` usa `Thread.sleep(forTimeInterval: 0.05)` in busy-wait loop con timeout 10 secondi. Se chiamato dal main thread, blocca la UI.
- Sintomo: UI freeze di fino a 10 secondi durante operazioni MCP che richiedono il file lock.
- Impatto: Esperienza utente degradata, apparente crash dell'app.
- Gravità: P1
- Strategia di fix minimo: Spostare l'acquisizione del lock su un thread di background o usare `DispatchSemaphore` con timeout. Aggiungere un `assert(!Thread.isMainThread)` come guardia.
- Commit previsto: `fix(mcp-shared-state): prevent advisory lock spin-wait on main thread`
