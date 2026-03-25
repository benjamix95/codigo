# Changelog — 2026-03-26: Persistence Bootstrap Crash Fix & Auto-Provisioning

## Sommario

Risolti 4 bug interconnessi nel layer di persistence che causavano crash dell'app
e fallimenti del bootstrap PostgreSQL. Aggiunta catena di auto-provisioning
completa: Homebrew → PostgreSQL → pgvector.

---

## Bug Fix

### Bug 1: EXC_BREAKPOINT su main thread (Categoria A — Critico)

- **Bug:** `ManagedPostgresService.bootstrapIfNeeded()` crashava con `EXC_BREAKPOINT` in DEBUG
- **Sintomo:** Crash immediato dell'app quando `persistenceStoreIfAvailable()` veniva chiamato dal main thread
- **Impatto:** Crash bloccante — l'app non poteva avviarsi se il bootstrap persistence veniva triggerato dalla UI
- **Causa:** `dispatchPrecondition(condition: .notOnQueue(.main))` in `#if DEBUG` — guardia eccessiva dato che la funzione è già thread-safe (usa `queue.sync` su coda custom `CoderEngine.Persistence.ManagedPostgres`, nessun rischio deadlock)
- **File modificato:** `Engine/CoderEngine/Sources/PersistenceCore/ManagedPostgresService.swift`
- **Fix:** Rimossa la `dispatchPrecondition`, sostituita con commento che documenta la thread-safety
- **Test di regressione:** `PersistenceBridgeMainThreadTests` — 3 test

### Bug 2: PgVectorInstaller falso positivo cross-version (Categoria A — Critico)

- **Bug:** `PgVectorInstaller.isInstalled()` ritornava `true` anche quando pgvector non era disponibile per la versione attiva di PostgreSQL
- **Sintomo:** Log "pgvector already installed" ma poi `CREATE EXTENSION vector` falliva con `could not open extension control file`
- **Impatto:** Bootstrap falliva completamente — nessuna feature di persistence funzionava
- **Causa:** `isInstalled()` controllava path statici hardcoded per pg@16/17. Trovava `vector.control` per pg@17 ma il runtime usava pg@14 che non aveva pgvector compilato
- **File modificato:** `Engine/CoderEngine/Sources/PersistenceCore/PgVectorInstaller.swift`
- **Fix:** `isInstalled()` ora rileva dinamicamente la major version attiva via `postgres --version` e verifica `vector.control` **solo** nella directory estensioni di quella versione. Rimosso il fallback cross-version che causava il falso positivo.

### Bug 3: ensureInstalled() non installava pgvector per versioni non coperte da Homebrew (Categoria A — Critico)

- **Bug:** `brew install pgvector` compilava solo per pg@17/18 (le build dependencies della formula), non per pg@14
- **Sintomo:** Dopo `brew install pgvector`, la versione attiva (pg@14) non aveva ancora pgvector
- **Impatto:** pgvector mai disponibile per utenti con versioni di PostgreSQL non coperte dalla formula Homebrew
- **File modificato:** `Engine/CoderEngine/Sources/PersistenceCore/PgVectorInstaller.swift`
- **Fix:** Se dopo `brew install` la versione attiva non ha pgvector, compila automaticamente dai sorgenti GitHub (`git clone --depth 1 pgvector` + `make PG_CONFIG=<path> install`)

### Bug 4: CREATE EXTENSION vector crashava l'intero migration script (Categoria B — Importante)

- **Bug:** Se pgvector non era disponibile, `CREATE EXTENSION IF NOT EXISTS vector` generava un ERROR SQL che faceva fallire l'intero script di migrazione
- **Sintomo:** Bootstrap fallito anche per tabelle non correlate a vector search
- **Impatto:** Tutto il layer di persistence inutilizzabile se pgvector mancava, anche se solo BM25 search era necessario
- **File modificato:** `Engine/CoderEngine/Sources/PersistenceCore/PersistenceSchema+VectorSearch.swift`
- **Fix:** `CREATE EXTENSION` wrappato in `DO $$ ... EXCEPTION WHEN OTHERS ... END $$`. Tabelle e indici vector creati solo se l'estensione è effettivamente caricata (`pg_extension` check). Se pgvector non è disponibile, emette solo un NOTICE e prosegue.

---

## Nuove Feature

### Auto-provisioning completo: Homebrew → PostgreSQL → pgvector

L'app ora installa automaticamente tutte le dipendenze necessarie al primo avvio.
L'utente non deve installare nulla manualmente.

#### Catena di installazione

1. **HomebrewInstaller** (`HomebrewInstaller.swift`)
   - Verifica se Homebrew è presente (`/opt/homebrew/bin/brew`)
   - Se assente, esegue lo script ufficiale di installazione con `NONINTERACTIVE=1`

2. **PostgresInstaller** (`PostgresInstaller.swift`)
   - Verifica se PostgreSQL è presente (`/opt/homebrew/bin/postgres`)
   - Se assente, esegue `brew install postgresql@17` + `brew link --overwrite`

3. **PgVectorInstaller** (aggiornato)
   - Rileva la major version attiva di PostgreSQL
   - Se pgvector non è presente per quella versione:
     - Tenta `brew install pgvector`
     - Se non copre la versione attiva, compila dai sorgenti GitHub

4. **ManagedPostgresService.bootstrapIfNeeded()** (aggiornato)
   - Prima di `validateBinaries()`, verifica se il binary `postgres` esiste
   - Se no, lancia la catena Homebrew → PostgreSQL
   - pgvector viene installato successivamente da `PostgresPersistenceStore`

---

## File Modificati

| File | Tipo | Descrizione |
|------|------|-------------|
| `ManagedPostgresService.swift` | fix | Rimossa dispatchPrecondition + aggiunto auto-provisioning pre-bootstrap |
| `PgVectorInstaller.swift` | fix + refactor | Detection dinamica versione, build from source, catena installer |
| `PersistenceSchema+VectorSearch.swift` | fix | SQL resiliente all'assenza di pgvector |

## File Aggiunti

| File | Tipo | Descrizione |
|------|------|-------------|
| `HomebrewInstaller.swift` | nuovo | Auto-installazione Homebrew |
| `PostgresInstaller.swift` | nuovo | Auto-installazione PostgreSQL via Homebrew |
| `PersistenceBridgeMainThreadTests.swift` | test | 3 test di regressione per crash main thread |

---

## Test

- **3 nuovi test** in `PersistenceBridgeMainThreadTests`:
  - `testBootstrapIfNeededDoesNotCrashOnMainThread` — regressione per EXC_BREAKPOINT
  - `testPersistenceStoreIfAvailableDoesNotCrashOnMainThread` — regressione entry point
  - `testBootstrapIfNeededWorksOnBackgroundThread` — verifica background thread

- **Test esistenti verificati** (tutti passano):
  - `ManagedPostgresBootstrapSafetyTests` — 6 test
  - `MCPSharedStatePostgresFallbackTests` — 5 test (prima fallivano per pgvector)
  - `PersistenceSchemaTests` — 1 test
  - `VectorSearchPersistenceTests` — test vector search
