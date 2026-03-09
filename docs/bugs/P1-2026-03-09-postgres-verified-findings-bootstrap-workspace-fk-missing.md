# P1 — Bootstrap PostgreSQL `VerifiedFindings` falliva se i `workspace_id` non esistevano ancora

## Categoria
Categoria A

## Bug
Durante l'import legacy di `VerifiedFindings`, `persistVerifiedFindingsEnvelope` inseriva `pipeline_runs` e `patch_artifacts` con `workspace_id` valorizzato senza garantire prima l'esistenza della riga corrispondente in `workspaces`.

## Sintomo
Il bootstrap falliva con errore PostgreSQL:

```text
insert or update on table "pipeline_runs" violates foreign key constraint "pipeline_runs_workspace_id_fkey"
DETAIL: Key (workspace_id)=(/tmp/workspace) is not present in table "workspaces".
```

## Impatto
- il bootstrap legacy verso PostgreSQL si interrompeva anche dopo la correzione della sintassi `pipeline_runs`
- l'app ricadeva sul fallback legacy JSON invece di completare il path DB-first
- il problema colpisce un'area fragile: persistence e replay di canonical snapshot

## Gravità
Alta

## Steps to reproduce
1. Salvare un `VerifiedFindingsSessionEnvelope` legacy con almeno un `VerifiedPipelineRun` o `VerifiedPatchArtifact` che referenzia un `workspaceId`.
2. Avviare `PersistenceBootstrapService.bootstrapIfNeeded()`.
3. Osservare il fallimento sulla foreign key di `workspaces`.

## Risultato attuale
L'import presuppone che i workspace referenziati esistano già nel DB.

## Risultato atteso
Il bootstrap deve materializzare in modo idempotente i `workspace_id` mancanti prima di inserire entità che li referenziano.

## Causa probabile
Il writer `VerifiedFindings` era stato costruito assumendo uno store già popolato, ma il percorso di bootstrap legacy importa snapshot canonici completi senza una fase separata di seed dei workspace.

## Scope consentito
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
- `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
- documentazione bug/changelog

## Non-scope
- schema PostgreSQL
- modellazione `Workspace`
- refactor del bootstrap generale

## Moduli confinanti da verificare
- `PersistenceBootstrapService`
- `LegacyPersistenceImportService`
- read path `MCPSharedStatePostgresFallbackTests`

## Test da aggiungere o aggiornare
- regressione bootstrap con `VerifiedPipelineRun` che usa un `workspaceId` non ancora presente in `workspaces`

## Strategia di fix minimo
- raccogliere gli `workspace_id` referenziati da `runs` e `patchArtifacts`
- fare upsert idempotente su `workspaces` prima degli insert con foreign key

## Verifica post-fix
- `PersistenceBootstrapIntegrationTests` verde con `run.workspaceId`
- `MCPSharedStatePostgresFallbackTests` verde sul read path PostgreSQL

## Fix applicato
- aggiunto seed idempotente di `workspaces` in `persistVerifiedFindingsEnvelope` prima degli insert su `pipeline_runs` e `patch_artifacts`
- mantenuta invariata la transazione e l'ordine logico del resto dell'import
