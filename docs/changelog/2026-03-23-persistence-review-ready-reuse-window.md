# 2026-03-23 — Persistence review ready reuse window

## Modifiche
- aggiunto in [PostgresPersistenceStore.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore.swift) un reuse window di 2 secondi per `ensureReady()`
- durante burst di scritture review consecutive lo store evita di ripetere bootstrap Postgres e `schemaVersion()` ad ogni SQL
- aggiunto test in [PersistenceSchemaTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Persistence/PersistenceSchemaTests.swift) per il comportamento del fast-path temporale

## Motivazione
- il sample del PID `5283` mostrava il main thread fermo nel path `writeCodeReviewSnapshot -> persistCodeReviewSnapshot -> ensureReady -> bootstrapIfNeeded/runPSQL`
- il fix riduce il lavoro sincrono ripetuto nel path caldo senza introdurre cache permanente dello stato DB

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/PersistenceSchemaTests -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests`
