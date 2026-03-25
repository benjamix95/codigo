# P0 — PgVectorInstaller falso positivo cross-version + bootstrap failure

## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** `PgVectorInstaller.isInstalled()` dava falso positivo e `CREATE EXTENSION vector` faceva fallire l'intero migration script
- **Sintomo:** Log "pgvector already installed" ma poi `ERROR: could not open extension control file "/opt/homebrew/share/postgresql@14/extension/vector.control": No such file or directory`
- **Impatto:** Tutto il layer di persistence inutilizzabile — bootstrap fallisce, nessun dato salvato in PostgreSQL
- **Gravità:** Bloccante per utenti con pg@14 o altre versioni non coperte da Homebrew pgvector
- **Steps to reproduce:**
  1. Avere PostgreSQL@14 come versione attiva (`/opt/homebrew/bin/postgres` → pg@14)
  2. Avere pgvector installato via Homebrew (compilato per pg@17/18)
  3. Avviare il bootstrap persistence
- **Risultato attuale:** `isInstalled()` ritorna `true` (trova vector.control per pg@17), ma `CREATE EXTENSION vector` fallisce su pg@14
- **Risultato atteso:** `isInstalled()` ritorna `false`, pgvector viene compilato per pg@14
- **Causa probabile:** Due bug concatenati:
  1. `isInstalled()` controllava path statici per pg@16/17 senza verificare la versione attiva
  2. `CREATE EXTENSION vector` in SQL diretto (non wrappato in exception handler) faceva fallire l'intero script
- **Scope consentito:** `PgVectorInstaller.swift`, `PersistenceSchema+VectorSearch.swift`
- **Non-scope:** `ManagedPostgresService.swift`, `PostgresPersistenceStore.swift` (toccato solo per auto-provisioning)
- **Moduli confinanti da verificare:** PersistenceSchema, PostgresPersistenceStore.ensureReady()
- **Test da aggiungere:** Coperti dai test esistenti `MCPSharedStatePostgresFallbackTests` (che ora passano)
- **Strategia di fix minimo:**
  1. `isInstalled()` → detection dinamica major version + check solo directory attiva
  2. `vectorSearchSQL` → wrappato in `DO $$ ... EXCEPTION ... END $$`
  3. Aggiunto build from source per versioni non coperte da Homebrew
- **Verifica post-fix:** Tutti i test persistence passano, inclusi i 5 test fallback che prima fallivano
- **Stato:** RISOLTO
