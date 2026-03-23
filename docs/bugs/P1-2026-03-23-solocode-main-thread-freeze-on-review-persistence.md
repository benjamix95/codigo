# P1 — 2026-03-23 — Freeze UI durante persistenza review snapshot

## Bug Fix Record
- Categoria: A — Critico
- Bug: l'app puo' bloccarsi sul main thread mentre persiste snapshot review tramite `MCPSharedState.writeCodeReviewSnapshot(...)`.
- Sintomo: UI ferma / app apparentemente congelata durante esecuzione review.
- Impatto: blocco dell'interfaccia utente nel flusso review; rischio timeout percepiti e impossibilita' di interazione.
- Gravita': alta
- Steps to reproduce:
  1. eseguire una review con aggiornamenti snapshot frequenti
  2. osservare un blocco della UI
  3. campionare il processo app
- Risultato attuale: il sample del PID `5283` mostra il main thread bloccato in:
  - `MCPSharedState.writeCodeReviewSnapshot`
  - `PostgresPersistenceStore.persistCodeReviewSnapshot`
  - `PostgresPersistenceStore.readVerifiedFindingsEnvelope`
  - `ManagedPostgresService.bootstrapIfNeeded` / `runPSQL`
- Risultato atteso: la persistenza review non deve bloccare il main thread.
- Causa probabile: path sincrono di persistenza/bootstrapping Postgres e health-check `psql` eseguiti dentro una catena chiamata dal main thread.
- Scope consentito:
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState+CodeReview.swift`
  - `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+ReviewAndPlan.swift`
  - `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore.swift`
  - `Engine/CoderEngine/Sources/PersistenceCore/ManagedPostgresService.swift`
- Non-scope:
  - redesign completo della persistence layer
  - migrazione storage review
- Moduli confinanti da verificare:
  - letture snapshot review
  - verified findings envelope
  - bootstrap Postgres
- Test da aggiungere o aggiornare:
  - test di non-regressione su persistenza review non bloccante o fast-path bootstrap
- Strategia di fix minimo:
  - ancora da implementare; priorita' alla rimozione del lavoro sincrono pesante dal main thread oppure a un fast-path sicuro sul bootstrap
- Verifica post-fix:
  - sample originale scritto in `/tmp/solocode-sample-5283.txt`
- Commit previsto: `fix(persistence): avoid main-thread review snapshot bootstrap`
