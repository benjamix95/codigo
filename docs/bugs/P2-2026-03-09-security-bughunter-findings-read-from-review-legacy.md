# P2 — `security_findings` e `bughunter_findings` passavano ancora dal read path review legacy

## Categoria
Categoria B

## Bug
Anche dopo il rollout del facade/shared state, i list path `security_findings` e `bughunter_findings` continuavano a dipendere da `readCodeReviewFindings` costruito sul bridge review storico.

## Sintomo
I due tool non avevano ancora una query surface dedicata del core shared per filtrare:
- `domain`
- `sourceOrigin`
- `kind`
- `stale/duplicate metadata`

## Impatto
Le superfici `Security` e `BugHunter` restavano ancora legate al layer review legacy proprio nei comandi di lettura più frequenti.

## Gravità
Media

## Riproduzione
1. Popolare una sessione con canonical finding `bug` e `security`.
2. Invocare `security_findings` o `bughunter_findings`.
3. Prima del fix, il path passava da helper review legacy invece di un query layer shared.

## Causa probabile
Il facade shared è arrivato per step; i comandi list/read non erano ancora stati riallineati.

## Fix applicato
- aggiunto `VerifiedFindingsQueryService`
- `security_findings` ora usa il query layer shared
- `bughunter_findings` ora usa il query layer shared
- aggiunte regressioni su query, security e bughunter
