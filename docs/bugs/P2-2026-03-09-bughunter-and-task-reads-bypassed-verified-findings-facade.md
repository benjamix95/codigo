# P2 — BugHunter e task payload leggevano VerifiedFindings senza passare dal facade condiviso

## Categoria
Categoria B

## Bug
Dopo l’introduzione del facade `VerifiedFindingsService`, alcune superfici secondarie continuavano a leggere projection/gate/replay in modo indiretto o incompleto.

## Sintomo
- `BugHunter` status non esponeva la source dell’envelope né il replay count derivato dal facade
- `TaskActivityStore.codeReviewPayload` non includeva metadata shared come source, replay count e gate ready

## Impatto
La promessa “una sola pipeline shared con più entrypoint” restava incompleta nelle superfici secondarie.

## Gravità
Media

## Riproduzione
1. Aprire `BugHunter` status su una run collegata a review session.
2. Leggere il payload del task activity per la stessa sessione.
3. Osservare che mancavano campi coerenti con il facade shared appena introdotto.

## Causa probabile
Il facade è arrivato dopo le prime integrazioni MCP/UI e questi path non erano ancora stati riallineati.

## Fix applicato
- `BugHunterHandler+Reads` ora espone metadata dal facade shared
- `TaskActivityStore+VerifiedFindings` include source/replay/gate nel payload del task
- aggiunti test di regressione MCP e app
