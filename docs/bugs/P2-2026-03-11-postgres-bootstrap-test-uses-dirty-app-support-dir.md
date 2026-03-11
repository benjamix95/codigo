# P2 - Il test Postgres bootstrap fallisce se la data dir locale esiste già ed è sporca

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: `MCPSharedStatePostgresFallbackTests` dipende da una data directory locale pulita in `~/Library/Application Support/CoderIDE/postgres/data`.
- Sintomo: il test fallisce con `initdb: directory ... exists but is not empty`.
- Impatto: una parte dei test persistence diventa dipendente dall’ambiente locale della macchina.
- Gravità: media.
- Steps to reproduce:
  1. lasciare una data dir Postgres non vuota in `~/Library/Application Support/CoderIDE/postgres/data`
  2. eseguire `xcodebuild test -scheme 'CoderEngineTests-Debug' -only-testing:CoderEngineTests/MCPSharedStatePostgresFallbackTests/testVerifiedFindingsDeltaPersistenceRemovesDeletedRowsAndReadsLatestEnvelope`
- Risultato attuale: il test fallisce in bootstrap `initdb`.
- Risultato atteso: il test deve usare una data dir isolata o ripulita per run.
- Causa probabile: il bootstrap test usa un percorso condiviso e persistente macchina-specifico.
- Causa probabile: confermata. `ManagedPostgresConfiguration.default` e `PersistenceTestSupport` usavano implicitamente `~/Library/Application Support/CoderIDE/postgres`, quindi i test ereditavano stato locale sporco.
- Scope consentito: test persistence Postgres e relativo harness di bootstrap.
- Non-scope: logica delta-write verificata in questa tranche.
- Moduli confinanti da verificare: `PersistenceBootstrapIntegrationTests`, `MCPSharedStatePostgresFallbackTests`, servizi bootstrap Postgres.
- Test da aggiungere o aggiornare: isolare data dir temporanea per i test.
- Strategia di fix minimo:
  - root directory e porta Postgres temporanei per i test
  - reset dell’ambiente che ferma il server sul root corrente prima di pulire
  - `ManagedPostgresService` reso sensibile agli override environment anche per l’istanza shared
- Verifica post-fix:
  - il test mirato non fallisce più con `initdb: directory exists but is not empty`
  - la persistence usa un root temporaneo dedicato al test-run corrente
  - resta instabilità separata del test harness `xctest`/codesign in alcuni run, già tracciata in bug distinto
- Commit previsto: tranche separata sidebar + test isolation
