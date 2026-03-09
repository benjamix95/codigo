# P1 — Security MCP handler accoppiato a enum non visibili nel target server

## Categoria
Categoria A

## Bug
Il nuovo wrapper MCP `Security` usava `FindingOrigin` e `FindingCategory` direttamente dentro il target `CoderIDEMCPServer`, causando un errore di compilazione del server MCP.

## Sintomo
La build falliva quando venivano compilati i file:
- `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/Security/SecurityHandler+Routing.swift`

## Impatto
Il workflow `Security` non era eseguibile né testabile. Di fatto i tool MCP `security_*` non potevano essere pubblicati.

## Gravità
Alta

## Riproduzione
1. Aggiungere il wrapper `Security` nel target `CoderIDEMCPServer`.
2. Compilare lo scheme `Solo Code-Debug`.
3. Osservare l'errore `cannot find 'FindingOrigin' in scope` / `cannot find 'FindingCategory' in scope`.

## Causa probabile
Accoppiamento diretto del target MCP a enum di dominio non importati o non disponibili nel modulo corrente.

## Fix applicato
L'handler `Security` ora usa i valori stringa canonici del backend review shared:
- `origin = "securityAuditor"`
- `category = "security"`

Questo mantiene il routing disaccoppiato dal dominio Swift tipizzato del modulo `CoderEngine`.

## Regressione da coprire
- test handler `Security` con filtro findings
- test di build/route dei tool `security_*`
