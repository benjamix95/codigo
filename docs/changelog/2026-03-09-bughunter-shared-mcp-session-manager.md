# 2026-03-09 — BugHunter crash da fd exhaustion su sessioni MCP duplicate

## Obiettivo
Eliminare la proliferazione di `coderide-mcp-server` e di pipe MCP causata dai runtime creati con manager di sessione indipendenti, che portava `BugHunter` a crashare su `errno: 24` quando tentava di aprire il lock file shared.

## Modifiche
- aggiunto `MCPSessionManager.shared` come singleton engine-level
- cambiato il default di `UnifiedToolRuntime.init(..., mcpSessions:)` da `MCPSessionManager()` a `.shared`
- aggiunto test di regressione che verifica che più `UnifiedToolRuntime()` di default riusino lo stesso session manager
- documentato il bug critico in `docs/bugs/P1-2026-03-09-bughunter-mcp-session-fd-exhaustion-crash.md`

## File toccati
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Session/MCPSessionManager.swift`
- `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Runtime/Contracts/UnifiedToolRuntime+RuntimeContracts.swift`
- `Tests/CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests.swift`
- `docs/bugs/P1-2026-03-09-bughunter-mcp-session-fd-exhaustion-crash.md`

## Evidenza del problema
- crash log di `Solo Code` su PID `68106`
- `BugHunterLock ... errno: 24`
- sample salvato in `/tmp/solo-code-68106.sample.txt`
- `open_fd_count=2665`
- `2544 PIPE`
- `21` processi `coderide-mcp-server --workspace .`

## Validazione prevista
Eseguire build e test mirati sull’area:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests \
  -only-testing:CoderEngineTests/MCPSessionManagerTests \
  -only-testing:SoloCodeAppTests/MCPRuntimeServiceTests
```

## Note
- Il fix è volutamente confinato: non cambia la semantica del BugHunter lock e non introduce refactor del command loop.
- Il problema osservato era di saturazione descriptor, non di permessi sul path `.lock`.
