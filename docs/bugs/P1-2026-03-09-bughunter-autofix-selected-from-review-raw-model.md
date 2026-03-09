# P1 — BugHunter autofix selezionava ancora il finding dal modello review raw

## Categoria
Categoria A

## Bug
Il path `BugHunter` di autofix continuava a scegliere il finding migliore leggendo direttamente `reviewSnapshot.findings`, invece di usare il canonical snapshot `VerifiedFindings`.

## Sintomo
La selezione `autofix` dipendeva ancora da campi review-specifici come `verifiedAt` e `confidence`, invece del backend shared e delle sue regole di dominio.

## Impatto
La pipeline restava parzialmente biforcata: `BugHunter` usava il core shared per molti read path, ma non per la decisione centrale dell’autofix.

## Gravità
Alta

## Riproduzione
1. Avviare una run `BugHunter` collegata a review session.
2. Chiedere `autofix_preview` o `autofix_apply`.
3. Osservare che la selezione del finding viene presa dal modello review raw.

## Causa probabile
Il lifecycle autofix era stato cablato prima del facade `VerifiedFindings` e non era ancora stato riallineato.

## Fix applicato
- introdotto `BugHunterAutofixSelectionService`
- selezione del finding autofixable spostata sul canonical snapshot `VerifiedFindings`
- refresh snapshot `BugHunter` riallineato al facade shared
- test di regressione sul filtro canonico e sulle superfici MCP/app già collegate

## Regressione da coprire
- selezione solo di finding `bug` e `verified`
- priorità per confidence più alta
- nessuna selezione di candidate o finding security
