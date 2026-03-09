# P1 — BugHunter non persisteva nel canonical store PostgreSQL se la conversation non esisteva

## Categoria
Categoria A

## Bug
Il writer PostgreSQL di `BugHunter` tentava di inserire `bug_hunter_runs.conversation_id` senza garantire prima l’esistenza della riga corrispondente in `conversations`.

## Sintomo
Con persistence PostgreSQL attiva, `writeBugHunterSnapshot` poteva fallire lato DB in silenzio; se il file legacy veniva poi rimosso o mancava dopo restart/crash, `readBugHunterSnapshot` restituiva `nil`.

## Impatto
La persistenza canonica di `BugHunter` non era affidabile. Una run poteva sparire dal path DB-first proprio nello scenario per cui il cutover serve: recovery senza file JSON.

## Gravità
Alta

## Steps to reproduce
1. Abilitare `SOLOCODE_ENABLE_POSTGRES_PERSISTENCE_IN_TESTS=1`.
2. Scrivere una `MCPSharedBugHunterSnapshot` con `conversationId` valorizzato.
3. Rimuovere il file legacy `bughunter/runs/<run>.json`.
4. Leggere di nuovo la snapshot tramite `MCPSharedState.readBugHunterSnapshot`.

## Risultato attuale
La lettura dal canonical store può tornare `nil` perché l’insert in `bug_hunter_runs` fallisce per FK verso `conversations`.

## Risultato atteso
La conversation deve essere upsertata prima del record `bug_hunter_runs`, così la snapshot resta leggibile dal DB anche senza storage legacy.

## Causa probabile
Il rollout DB-first di `review` e `plan` aveva già l’upsert della conversation; il path `BugHunter` era rimasto indietro.

## Scope consentito
- `Engine/CoderEngine/Sources/PersistenceCore/PostgresPersistenceStore+ReviewAndPlan.swift`
- test persistence/bughunter correlati
- documentazione bug/changelog

## Non-scope
- state machine `BugHunter`
- command API MCP
- refactor dei bridge review/debug non necessari al fix

## Moduli confinanti da verificare
- `MCPSharedState+BugHunter`
- `BugHunterHandlerTests`
- persistence bootstrap e fallback DB-first

## Test da aggiungere o aggiornare
- regressione `MCPSharedStatePostgresFallbackTests.testBugHunterReadsFromPostgresWhenLegacyFileIsMissing`
- smoke test `MCPSharedBugHunterCommandsTests`
- smoke test `BugHunterHandlerTests`

## Strategia di fix minimo
- upsert di `conversations` prima dell’`INSERT ... bug_hunter_runs`
- nessun cambiamento ai contratti pubblici

## Verifica post-fix
- test isolato sul fallback Postgres BugHunter verde
- suite persistence/bridge verde
- test BugHunter handler/commands verdi

## Fix applicato
- `persistBugHunterSnapshot` ora crea/aggiorna la `conversation` prima di inserire `bug_hunter_runs`
- mantenuto invariato il bridge legacy come fallback transitorio
- confermato il recupero da DB anche dopo rimozione del file legacy
