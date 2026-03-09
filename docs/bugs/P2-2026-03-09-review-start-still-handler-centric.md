# P2 — `review_start` era ancora handler-centric invece che service-driven

## Categoria
Categoria B

## Bug
L’avvio della review era ancora validato e accodato dentro l’handler MCP, e `bughunter_start` costruiva lo start review con logica propria.

## Sintomo
La queue di start non passava da un service shared del core e review/bughunter non usavano la stessa surface di avvio.

## Impatto
Rischio di drift tra entrypoint diversi per:
- validazione scope/ref
- validazione backend
- validazione session id
- duplicate queued session

## Gravità
Media

## Causa probabile
Il core shared è stato introdotto dopo l’handler review originale, quindi lo start era rimasto fuori dal refactor.

## Fix applicato
- introdotto `VerifiedFindingsStartCommandService`
- `review_start` ora usa il service shared
- `bughunter_start` ora usa lo stesso service per enqueue del review start

## Regressione da coprire
- invalid scope
- missing ref
- duplicate queued session
- payload normalizzato con conversation/session
