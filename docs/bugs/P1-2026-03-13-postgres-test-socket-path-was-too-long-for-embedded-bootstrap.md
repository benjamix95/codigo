# P1 - I test persistence usavano un socket path PostgreSQL troppo lungo

## Bug Fix Record
- Categoria: A
- Bug: i test persistence configuravano `SOLOCODE_POSTGRES_ROOT_DIRECTORY` con path temporanei troppo lunghi, superando il limite effettivo del socket Unix di PostgreSQL.
- Sintomo: `HistoricalFindingsQueryServiceTests` e suite derivate fallivano con `pg_ctl: could not start server` durante il bootstrap embedded.
- Impatto: validator `solocode-validate` non completabile in verde sul perimetro review, nonostante il core Rust e i test panel fossero corretti.
- Gravita': alta, perche' blocca la validazione automatica obbligatoria.
- Steps to reproduce:
  1. Eseguire `xcodebuild test -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests`.
  2. Lasciare che il test imposti `SOLOCODE_POSTGRES_ROOT_DIRECTORY` sotto `tmp/solocode-postgres-tests-<uuid>`.
  3. Osservare il bootstrap fallire prima ancora dell'esecuzione del test.
- Risultato attuale: il server PostgreSQL embedded non partiva nei test persistence.
- Risultato atteso: i test persistence devono usare un root path corto e deterministico, compatibile con i socket Unix di PostgreSQL.
- Causa probabile: il path `.../solocode-postgres-tests-<uuid>/socket/.s.PGSQL.<port>` superava il limite del filesystem locale.
- Scope consentito:
  - `Tests/CoderEngineTests/Persistence/PersistenceTestSupport.swift`
  - `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift`
  - `Engine/CoderEngine/Sources/PersistenceCore/PersistenceModels.swift`
  - documentazione `docs/bugs`, `docs/changelog`
- Non-scope:
  - logica SQL del persistence store
  - schema o migrazioni PostgreSQL
- Moduli confinanti da verificare:
  - `HistoricalFindingsQueryServiceTests`
  - `ReviewPanelFindingsHistoryTests`
  - validator `solocode-validate`
- Test da aggiungere o aggiornare:
  - nessun nuovo test; la prova e' il bootstrap verde dei test persistence esistenti
- Strategia di fix minimo:
  - usare prefisso root corto (`scpg-*`) nei test
  - allineare anche il root di default in ambiente XCTest
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/HistoricalFindingsQueryServiceTests`
  - `./scripts/solocode-validate --trigger gitCommit --workspace /Users/benjaminstoica/SoloCode --staged`
- Commit previsto: `fix(persistence-tests): shorten postgres socket root path`
