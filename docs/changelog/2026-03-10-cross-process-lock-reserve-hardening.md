# 2026-03-10 — Hardening reserve FD del lock cross-process

## Obiettivo
Chiudere due regressioni introdotte nell’hardening del lock advisory shared-state: reserve FD non ripristinata dopo il primo `EMFILE` e allocazione implicita/leak del reserve di default.

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CrossProcessLock.swift`
  - `EmergencyLockDescriptorReserve` chiude ora il descriptor anche in `deinit`
  - `withAdvisoryFileLock(...)` non crea più una reserve implicita per i call site generici
  - il teardown del ramo `.locked` esegue ora `LOCK_UN`, `close(descriptor)` e solo dopo `replenishIfNeeded()`
  - `acquireAdvisoryFileLock(...)` accetta una reserve opzionale
- aggiornato `Tests/CoderEngineTests/CodeReview/MCPSharedCodeReviewSnapshotStoreTests.swift`
  - aggiunge una regressione che verifica il refill della reserve dopo un lock riuscito
  - aggiunge una regressione che verifica l’assenza di leak FD nel path default del helper
- documentati i due bug in `docs/bugs/`

## Validazione prevista
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`

## Impatto atteso
- la reserve FD resta riutilizzabile dopo ogni recovery da `EMFILE/ENFILE`
- il helper generico non introduce più pressione artificiale sui file descriptor
- resta invariato il comportamento dei wrapper review/BugHunter con reserve statica dedicata
