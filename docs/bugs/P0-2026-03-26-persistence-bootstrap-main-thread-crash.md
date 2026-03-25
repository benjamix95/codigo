# P0 — EXC_BREAKPOINT in bootstrapIfNeeded() su main thread

## Bug Fix Record

- **Categoria:** A — Critico
- **Bug:** `ManagedPostgresService.bootstrapIfNeeded()` crasha con `EXC_BREAKPOINT` quando chiamato dal main thread
- **Sintomo:** Crash immediato (Task 13: EXC_BREAKPOINT code=1) alla riga `dispatchPrecondition(condition: .notOnQueue(.main))`
- **Impatto:** App crasha all'avvio quando qualsiasi codice UI triggera il persistence layer
- **Gravità:** Bloccante — impedisce l'uso dell'app
- **Steps to reproduce:**
  1. Qualsiasi chiamata a `MCPSharedState.persistenceStoreIfAvailable()` dal main thread
  2. Es: lettura code review, bug hunter, plan, verified findings dalla UI
- **Risultato attuale:** `EXC_BREAKPOINT` crash
- **Risultato atteso:** Bootstrap eseguito correttamente o fallback al legacy storage
- **Causa probabile:** `dispatchPrecondition(condition: .notOnQueue(.main))` in `#if DEBUG` — guardia eccessiva. La funzione è thread-safe (usa `queue.sync` su `DispatchQueue(label: "CoderEngine.Persistence.ManagedPostgres")`, coda custom separata dal main queue, nessun rischio deadlock)
- **Scope consentito:** `ManagedPostgresService.swift` riga 16-19
- **Non-scope:** `MCPSharedState+PersistenceBridge.swift`, callers, UI layer
- **Moduli confinanti da verificare:** PersistenceBootstrapService, PostgresPersistenceStore, MCPSharedState bridge
- **Test da aggiungere:** `PersistenceBridgeMainThreadTests` — 3 test di regressione
- **Strategia di fix minimo:** Rimuovere `dispatchPrecondition`, sostituire con commento sulla thread-safety
- **Verifica post-fix:** Tutti i test persistence passano, nessun crash su main thread
- **Stato:** RISOLTO
