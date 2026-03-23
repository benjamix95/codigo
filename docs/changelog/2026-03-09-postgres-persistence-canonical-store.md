# 2026-03-09 — PostgreSQL persistence canonical store

## Obiettivo
Introdurre un layer di persistenza PostgreSQL locale e gestito dall’app come canonical store per `VerifiedFindingsCore`, `Planning Engine`, `Debug Engine` e bridge `review` / `BugHunter`, mantenendo compatibili le API esistenti e lasciando i file legacy come fallback transitorio.

## Modifiche
- aggiunto il nuovo modulo `PersistenceCore` con bootstrap, schema SQL, import legacy, store/repository SQL-first e supporto runtime:
  - `ManagedPostgresService`
  - `PersistenceBootstrapService`
  - `PostgresPersistenceStore`
  - schema splittato per dominio (`Metadata`, `VerifiedFindings`, `Planning`, `Debug`, `Projection`)
- introdotto bootstrap app dedicato in `SoloCodeApp+Persistence` e hookup in `SoloCodeApp.swift`
- convertiti i bridge `MCPSharedState` a lettura/scrittura DB-first con fallback legacy per:
  - `VerifiedFindings`
  - `CodeReview`
  - `BugHunter`
  - `Plan`
- aggiunti test dedicati per:
  - integrità schema
  - bootstrap/import legacy
  - fallback DB-first dei bridge MCP
- corretto il bootstrap PostgreSQL locale:
  - quoting corretto del path `Application Support`
  - `schemaVersion()` tollera database vuoto senza `schema_migrations`
- corretto un difetto emerso durante la rollout:
  - `persistBugHunterSnapshot` ora fa upsert della `conversation` prima di scrivere `bug_hunter_runs`, evitando failure FK e perdita dello stato canonical

## File toccati
- `App/SoloCodeApp/Sources/App/Bootstrap/SoloCodeApp.swift`
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+Persistence.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+BugHunter.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReview.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReviewIndex.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+PersistenceBridge.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+VerifiedFindings.swift`
- `Engine/CoderEngine/Sources/Infrastructure/MCP/Plan/MCPSharedState+Plan.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceModels.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/ManagedPostgresService.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceBootstrapService.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/LegacyPersistenceImportService.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+ReviewAndPlan.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+Metadata.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+VerifiedFindings.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+Planning.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+Debug.swift`
- `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+Projection.swift`
- `Tests/CoderEngineTests/Persistence/PersistenceTestSupport.swift`
- `Tests/CoderEngineTests/Persistence/PersistenceSchemaTests.swift`
- `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
- `Tests/CoderEngineTests/Persistence/MCPSharedStatePostgresFallbackTests.swift`
- `Solo Code.xcodeproj/project.pbxproj`

## Validazione
Eseguita con `xcodebuild` su macOS:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/PersistenceSchemaTests \
  -only-testing:CoderEngineTests/PersistenceBootstrapIntegrationTests \
  -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests \
  -only-testing:CoderEngineTests/VerifiedFindingsSharedStateTests \
  -only-testing:CoderEngineTests/MCPSharedCodeReviewSnapshotStoreTests \
  -only-testing:CoderEngineTests/MCPSharedPlanStateTests

xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/MCPSharedBugHunterCommandsTests \
  -only-testing:CoderEngineTests/BugHunterHandlerTests
```

Esito:
- suite persistence/bridge verde
- suite BugHunter confinante verde
- nessuna failure residua nei test eseguiti

## Note
- Il layer resta SQL-first: nessun ORM introdotto.
- Le projection restano non-authoritative e ricostruibili.
- I file legacy non sono più la source of truth, ma restano come fallback transitorio dove il processo MCP non è ancora tagliato completamente sul DB.
