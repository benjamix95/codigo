# P2 — La logica checkpoint/replay di VerifiedFindings era dispersa tra bridge e storage

## Categoria
Categoria B

## Bug
Il backend `VerifiedFindings` aveva già snapshot canonica e checkpoint persistiti, ma la logica di recupero e rebuild restava sparsa tra bridge `CodeReviewSessionSnapshot` e helper di storage `MCPSharedState`.

## Sintomo
I read path usavano fallback diversi a seconda del chiamante, senza un service layer dedicato per:
- recupero envelope
- scelta della source of truth
- replay del projection model

## Impatto
Meno prevedibilità del backend shared e maggiore rischio di divergenze future tra panel, chat e MCP reads.

## Gravità
Media

## Riproduzione
1. Persistire una sessione `VerifiedFindings`.
2. Leggerla da bridge e read model diversi.
3. Osservare che il recupero dell’envelope dipendeva da helper separati invece di un service condiviso.

## Causa probabile
Persistenza e rebuild sono arrivati in tranche successivi, senza ancora estrarre un service applicativo unico.

## Fix applicato
- introdotti service layer dedicati per:
  - recovery da checkpoint
  - replay summary del projection model
- i bridge e i read model ora usano il service condiviso invece di fallback ad hoc

## Regressione da coprire
- preferenza per envelope persistito
- rebuild da canonical snapshot
- replay summary coerente con projection rebuilt
