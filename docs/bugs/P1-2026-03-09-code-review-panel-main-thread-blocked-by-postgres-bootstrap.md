# P1 — Il panel review bloccava il main thread durante la persistenza PostgreSQL

## Categoria
Categoria A

## Bug
`TaskActivityStore.ingestCodeReviewSnapshot` persisteva il `CodeReviewSessionSnapshot` in modo sincrono sul main thread tramite `MCPSharedState.writeCodeReviewSnapshot`.

## Sintomo
Durante l’avvio di una review o la ricezione di snapshot iniziali, l’app poteva congelarsi. Il sample del PID mostrava:

```text
CodeReviewPanelStore.startReview
 -> TaskActivityStore.ingestCodeReviewSnapshot
 -> MCPSharedState.writeCodeReviewSnapshot
 -> PostgresPersistenceStore.ensureReady
 -> ManagedPostgresService.runProcess(...).waitUntilExit
```

## Impatto
- freeze della UI review/chat mentre bootstrap PostgreSQL e `psql` partono o verificano lo schema
- esperienza percepita come app bloccata anche senza crash
- rischio alto nelle aree fragili review/persistence/bridge UI-runtime

## Gravità
Alta

## Steps to reproduce
1. Avviare l’app con persistenza PostgreSQL attiva.
2. Iniziare una code review o forzare l’ingest di uno snapshot review sul panel.
3. Se `ensureReady()` deve bootstrapparsi o lanciare `psql`, osservare il blocco dell’interfaccia.
4. Eseguire `sample <pid-app> 5`.

## Risultato attuale
La persistenza cross-process della review può eseguire bootstrap e process spawn sul thread UI.

## Risultato atteso
La UI deve aggiornare stato e attività subito; la persistenza MCP/PostgreSQL deve avvenire fuori dal main thread mantenendo ordine dei write.

## Causa probabile
Il bridge review -> `TaskActivityStore` era stato progettato per pubblicare stato e persisterlo nello stesso metodo `@MainActor`, senza delegare l’I/O a una coda dedicata.

## Scope consentito
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore.swift`
- `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+CodeReview.swift`
- nuovo bridge di persistenza task activity
- test `SoloCodeAppTests` correlati
- documentazione bug/changelog

## Non-scope
- refactor del bootstrap PostgreSQL
- lifecycle `CodeReviewSessionState`
- accumulo processi `coderide-mcp-server` non direttamente coinvolti nel sample del freeze

## Moduli confinanti da verificare
- `CodeReviewPanelStore+Launch`
- `TaskActivityStore`
- `MCPSharedState+CodeReview`

## Test da aggiungere o aggiornare
- regressione che dimostri che `ingestCodeReviewSnapshot` non persiste più inline sul main thread
- verifica che l’ordine dei write resti seriale

## Strategia di fix minimo
- introdurre un bridge di persistenza seriale dedicato
- lasciare invariato il contratto pubblico di `TaskActivityStore`
- spostare il solo `writeCodeReviewSnapshot` fuori dal main thread

## Verifica post-fix
- sample coerente con rimozione del path bloccante dal main thread
- test `SoloCodeAppTests` sul bridge e sull’ingest verdi

## Fix applicato
- aggiunto `TaskActivityPersistenceBridge` con coda seriale utility
- `TaskActivityStore.ingestCodeReviewSnapshot` ora delega la persistenza review in background
- aggiunti test che verificano defer asincrono e ordine dei write
