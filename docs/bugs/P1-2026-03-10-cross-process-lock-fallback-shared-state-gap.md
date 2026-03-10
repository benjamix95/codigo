# P1 — Fallback del lock shared-state senza esclusione cross-process

## Bug Fix Record
- Categoria: A
- Bug: il fallback del wrapper `withAdvisoryFileLock(...)` eseguiva il body protetto solo da `NSRecursiveLock`, perdendo coordinamento tra processi.
- Sintomo: un caller sul percorso fallback poteva correre in parallelo con un altro caller che usava ancora correttamente `flock(...)`.
- Impatto: rischio di corruzione degli snapshot condivisi di code review / verified findings / BugHunter.
- Gravità: alta
- Steps to reproduce:
  1. Forzare un caller su `withAdvisoryFileLock(...)` a restituire `.fallback(EMFILE)`.
  2. Eseguire in parallelo un secondo caller sul percorso advisory normale.
  3. Entrambi attraversano la sezione critica senza coordinarsi.
- Risultato attuale: il fallback serializzava solo il processo corrente.
- Risultato atteso: anche il fallback deve condividere la stessa barriera cross-process del percorso normale.
- Causa probabile: introduzione di un fallback locale per evitare `fatalError`, senza una primitive comune tra path advisory e path fallback.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewSnapshotStoreTests.swift`
- Non-scope:
  - redesign completo della persistenza shared-state
  - modifica dei call site MCPSharedState
- Moduli confinanti da verificare:
  - `MCPSharedState+CodeReview.swift`
  - `MCPSharedState+VerifiedFindings.swift`
  - `MCPSharedState+BugHunter*.swift`
- Test da aggiungere o aggiornare:
  - regressione mista fallback + advisory sullo stesso lock
- Strategia di fix minimo:
  - introdurre una barriera cross-process condivisa fra percorso advisory e fallback
  - mantenere la reentrancy sicura nello stesso thread/processo
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`
- Commit previsto: `fix(mcp): keep shared-state lock cross-process on fallback`

## Evidenza
- il nuovo test di regressione forza un caller su `.fallback(EMFILE)` e uno sul percorso advisory normale, verificando che non entrino mai contemporaneamente nella stessa sezione critica
