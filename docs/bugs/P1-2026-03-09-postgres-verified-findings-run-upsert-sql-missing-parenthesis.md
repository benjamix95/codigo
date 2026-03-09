# P1 — Bootstrap PostgreSQL falliva importando `VerifiedPipelineRun` dal canonical snapshot

## Categoria
Categoria A

## Bug
Lo store PostgreSQL di `VerifiedFindings` generava uno statement `INSERT INTO pipeline_runs ... ON CONFLICT` malformato: mancava la parentesi di chiusura della clausola `VALUES`.

## Sintomo
Durante il bootstrap o la persistenza di una sessione con almeno un `VerifiedPipelineRun`, `psql` falliva con:

```text
ERROR: syntax error at or near "ON"
```

e il runtime ricadeva sul fallback legacy.

## Impatto
- il canonical store PostgreSQL non riusciva a materializzare sessioni `VerifiedFindings` con run persistite
- `PersistenceBootstrapService` poteva fallire all’avvio pur con schema valido
- review / bughunter / sicurezza perdevano affidabilità del path DB-first e tornavano al fallback JSON

## Gravità
Alta

## Steps to reproduce
1. Abilitare `SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS=1`.
2. Salvare un `VerifiedFindingsSessionEnvelope` legacy contenente almeno un `VerifiedPipelineRun`.
3. Eseguire `PersistenceBootstrapService.bootstrapIfNeeded()`.
4. Osservare il fallimento `psql` su `ON CONFLICT`.

## Risultato attuale
Il bootstrap interrompe l’import del canonical snapshot quando incontra la persistenza di `pipeline_runs`.

## Risultato atteso
L’`INSERT INTO pipeline_runs` deve chiudere correttamente la lista `VALUES`, consentire l’upsert e completare l’import legacy verso PostgreSQL.

## Causa probabile
Errore di formattazione manuale nello statement SQL multi-line di `persistVerifiedFindingsEnvelope`, non coperto dai test precedenti perché il caso di bootstrap non includeva `runs`.

## Scope consentito
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+VerifiedFindings.swift`
- `Tests/CoderEngineTests/Persistence/PersistenceBootstrapIntegrationTests.swift`
- documentazione bug/changelog

## Non-scope
- schema PostgreSQL
- bridge MCP
- warning `AttributeGraph`, `ViewBridge`, indexing o discovery MCP `node`/`npx`

## Moduli confinanti da verificare
- `PersistenceBootstrapService`
- fallback DB-first `MCPSharedState+VerifiedFindings`
- import legacy `VerifiedFindings`

## Test da aggiungere o aggiornare
- regressione bootstrap con `VerifiedPipelineRun` presente nel canonical snapshot

## Strategia di fix minimo
- aggiungere solo la parentesi mancante nello statement `pipeline_runs`
- estendere il test di bootstrap esistente con un run persistito

## Verifica post-fix
- `PersistenceBootstrapIntegrationTests` verde con envelope che contiene `runs`
- smoke test sui fallback PostgreSQL `VerifiedFindings` / `Plan`

## Fix applicato
- chiusa correttamente la clausola `VALUES` prima di `ON CONFLICT` in `persistVerifiedFindingsEnvelope`
- esteso il test di bootstrap per importare e rileggere un `VerifiedPipelineRun` dal canonical store
