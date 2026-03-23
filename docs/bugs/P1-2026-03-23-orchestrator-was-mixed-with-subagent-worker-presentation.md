# P1 — Orchestrator mescolato ai subagent nella rappresentazione chat

## Problemi trovati

### 1. Fallback `orchestrator` nel reducer delle card worker
- Gravità: P1
- Sintomo: eventi swarm senza owner esplicito finivano nel reducer delle card come pseudo-worker `orchestrator`.
- Impatto: la UI doveva filtrare a valle una falsa subagent identity e il modello concettuale risultava ambiguo.
- Stato: corretto il 2026-03-23.

### 2. Terminologia incoerente tra orchestrator, worker e subagent
- Gravità: P2
- Sintomo: help text, pipeline mapping e UI usavano in modo alternato `agent`, `subagent`, `worker` e `orchestrator`.
- Impatto: difficile capire se il planner fosse un worker reale o una fase interna del supervisor.
- Stato: corretto il 2026-03-23 con naming UX coerente e payload di ownership espliciti.

### 3. Mancanza di supervisor trace separata
- Gravità: P2
- Sintomo: la chat mostrava worker/subagent e trace generico, ma non una traccia distinta del supervisor.
- Impatto: eventi di coordinamento, scheduling e routing risultati si confondevano con il lavoro dei subagent.
- Stato: corretto il 2026-03-23.
