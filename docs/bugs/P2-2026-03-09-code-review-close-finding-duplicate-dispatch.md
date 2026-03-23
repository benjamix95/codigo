# P2 — close_finding gestito due volte nel command loop review

## Categoria
Categoria B

## Bug
L'azione `close_finding` compariva sia nel ramo del patch workflow sia in un case separato dello switch del command loop review.

## Sintomo
Durante la compilazione compariva un warning di pattern duplicato su:
- `App/SoloCodeApp/Sources/App/Bootstrap/Sections/SoloCodeApp+CodeReviewCommands.swift`

## Impatto
Il warning non bloccava la build, ma rendeva ambiguo il percorso di dispatch e aumentava il rischio di divergenza futura tra lifecycle patch e chiusura finding.

## Gravità
Media

## Riproduzione
1. Compilare lo scheme `Solo Code-Debug`.
2. Osservare il warning su `close_finding` duplicato nello switch.

## Causa probabile
Introduzione incrementale del lifecycle `revalidate/rollback/close` senza rimuovere il vecchio ramo dedicato.

## Fix applicato
`close_finding` resta gestito solo dal path condiviso `handlePatchWorkflowCommand`, eliminando il ramo duplicato.

## Regressione da coprire
- test MCP `review_close_finding`
- test handler `security_close_finding` che riusa lo stesso workflow shared
