# P2 — M mancava un facade di dominio VerifiedFindings condiviso

## Categoria
Categoria B

## Bug
Il core `VerifiedFindings` aveva già servizi puntuali per sync, gate, checkpoint e replay, ma mancava ancora un facade applicativo unico che componesse questi pezzi per i chiamanti.

## Sintomo
Bridge, handler MCP e read model usavano combinazioni diverse di:
- `VerifiedFindingsCheckpointService`
- `VerifiedFindingsReplayService`
- `VerifiedFindingsSecurityGateService`
- fallback diretti al sync service

## Impatto
Maggiore rischio di divergenza tra panel/chat/MCP e minore chiarezza sull’entrypoint corretto del core shared.

## Gravità
Media

## Riproduzione
1. Leggere projection da bridge.
2. Leggere status da MCP.
3. Leggere gate da `SecurityHandler`.
4. Osservare che ogni path componeva manualmente i servizi sottostanti invece di usare un facade unico.

## Causa probabile
Il core è stato costruito per tranche successive, ma il service layer unificante era rimasto implicito.

## Fix applicato
- introdotto `VerifiedFindingsService`
- uniformato l’uso del core shared in:
  - bridge `CodeReviewSessionSnapshot`
  - `MCPSharedState+CodeReviewReads`
  - `SecurityHandler+Routing`

## Regressione da coprire
- resolve da snapshot con envelope persistito
- resolve da session id con rebuild canonico
- replay/gate coerenti via facade
