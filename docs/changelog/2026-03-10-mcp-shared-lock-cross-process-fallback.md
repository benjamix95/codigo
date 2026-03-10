# 2026-03-10 — Shared-state lock fallback con barriera cross-process

## Modifiche
- `withAdvisoryFileLock(...)` acquisisce ora una barriera cross-process comune prima del percorso advisory o fallback
- il fallback non usa più solo un lock locale: resta coordinato con il percorso advisory normale
- aggiunta una guardia di reentrancy per evitare deadlock su accessi nidificati dello stesso thread

## Test
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests`
- esito: `TEST SUCCEEDED`

## Rischio controllato
- nessuna modifica ai call site di `MCPSharedState`
- nessun refactor del formato di persistenza
