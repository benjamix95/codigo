# 2026-03-09 — Fix bootstrap PostgreSQL `VerifiedFindings` con `pipeline_runs`

## Obiettivo
Ripristinare il bootstrap/import PostgreSQL del canonical store `VerifiedFindings` quando il payload legacy contiene uno o più `VerifiedPipelineRun`.

## Modifiche
- corretto `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`:
  - aggiunta la parentesi di chiusura mancante nella `VALUES (...)` dell’`INSERT INTO pipeline_runs`
  - mantenuto invariato l’upsert `ON CONFLICT (id)` e il resto della transazione
- aggiornato `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`:
  - il fixture di bootstrap ora include un `VerifiedPipelineRun`
  - il test verifica che l’envelope importata da PostgreSQL contenga anche il run persistito

## Validazione prevista
Eseguire su macOS con `xcodebuild`:

```bash
xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/PersistenceBootstrapIntegrationTests/testBootstrapImportsLegacyVerifiedFindingsAndPlanState \
  -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests/testVerifiedFindingsReadsFromPostgresWhenLegacyFilesAreMissing
```

## Note
- Fix confinato al writer SQL `VerifiedFindings`; nessun refactor del layer persistence.
- Restano fuori scope i warning di startup non correlati (`AttributeGraph`, `ViewBridge`, discovery MCP `node`/`npx`).
