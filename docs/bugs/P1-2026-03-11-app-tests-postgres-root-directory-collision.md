# P1 — I test app di history persistence riusavano una root Postgres process-based e collidevano sui rerun

## Bug Fix Record
- Categoria: A
- Bug: `ReviewPanelFindingsHistoryTests` usava la root directory Postgres di default legata al PID del processo test host, con collisioni fra run successivi nella stessa sessione.
- Sintomo: `initdb: error: directory .../solocode-postgres-tests-<pid>/data exists but is not empty`.
- Impatto: test di regressione persistence/history non affidabili, falsi negativi in validazione.
- Gravità: alta lato affidabilità del harness.
- Steps to reproduce:
  1. eseguire ripetutamente la suite `ReviewPanelFindingsHistoryTests`.
  2. lasciare residui nel bootstrap Postgres del test host.
  3. rieseguire il test persistence.
  4. osservare il failure su `initdb`.
- Risultato attuale: i test app non isolavano `SOLOCODE_POSTGRES_ROOT_DIRECTORY` e `SOLOCODE_POSTGRES_PORT`, a differenza dei test engine.
- Risultato atteso: ogni run dei test app che abilita persistence deve usare root directory UUID-based e porta dedicata, con cleanup del relativo override.
- Causa probabile: helper locale duplicato e meno robusto rispetto a `PersistenceTestSupport` dei test engine.
- Scope consentito:
  - `Tests/SoloCodeAppTests/ReviewPanelFindingsHistoryTests.swift`
  - documentazione/changelog
- Non-scope:
  - refactor del bootstrap persistence globale
  - modifica del service PostgreSQL di produzione
- Moduli confinanti da verificare:
  - `ReviewPanelFindingsHistoryTests`
  - altre suite persistence che usano override env
- Test da aggiungere o aggiornare:
  - nessun nuovo test dedicato; hardening degli helper del test esistente
- Strategia di fix minimo:
  - allineare gli helper del test app a quelli dei test engine
  - impostare `SOLOCODE_POSTGRES_ROOT_DIRECTORY` UUID-based e `SOLOCODE_POSTGRES_PORT`
  - pulire la root override prima di resettare le env
- Verifica post-fix:
  - rerun della suite history senza nuovo errore `data exists but is not empty`
  - residuo failure solo sul launcher Xcode locale, non più sul bootstrap Postgres
- Commit previsto: `test(history): isolate postgres bootstrap roots per app test run`
