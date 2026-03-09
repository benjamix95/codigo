# 2026-03-09 — Hardening bootstrap PostgreSQL `VerifiedFindings` per foreign key `workspaces`

## Obiettivo
Consentire al bootstrap legacy di importare `VerifiedFindings` che referenziano `workspace_id` non ancora presenti nel database.

## Modifiche
- aggiornato `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
  - raccolti gli `workspaceId` referenziati da `runs` e `patchArtifacts`
  - aggiunto upsert idempotente in `workspaces` prima degli insert con foreign key
- riusato `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
  - il fixture con `VerifiedPipelineRun(workspaceId: "/tmp/workspace")` ora copre anche il seed dei workspace mancanti

## Validazione eseguita
```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/PersistenceBootstrapIntegrationTests \
  -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests/testVerifiedFindingsReadsFromPostgresWhenLegacyFilesAreMissing
```

## Note
- hardening confinato al writer PostgreSQL `VerifiedFindings`
- nessun cambio di schema o refactor del bootstrap generale
