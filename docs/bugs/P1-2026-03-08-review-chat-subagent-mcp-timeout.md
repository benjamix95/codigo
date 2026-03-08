# P1 — Review chat subagent MCP timeout

## Bug Fix Record
- Categoria: B
- Bug: nella chat di code review il launch di `coderide_subagent_explorer` andava in timeout invece di partire subito.
- Sintomo: l'activity stream mostrava `tool call failed` dopo `timed out awaiting tools/call after 120s`.
- Impatto: la review chat non riusciva ad avviare gli explorer/reviewer/security subagents, quindi il flusso di bug hunting si interrompeva sul primo round operativo.
- Gravità: P1
- Steps to reproduce:
  1. Aprire la chat del code review.
  2. Avviare una conversazione che usa `coderide_subagent_explorer`.
  3. Attendere la risposta del tool MCP.
- Risultato attuale: la call resta nel runtime MCP e termina in timeout.
- Risultato atteso: il server MCP deve ackare subito il tool subagent e lasciare alla pipeline eventi/UI la gestione del lifecycle.
- Causa probabile: `CoderIDEMCPServerApp+IDEStateTools` trattava review/bughunter/policy come tool pass-through, ma non includeva `subagent_*`, quindi il server eseguiva il runtime reale invece di restituire conferma immediata.
- Scope consentito: `Tools/CoderIDEMCPServer/Sources/Runtime/Handlers/CoderIDEMCPServerApp+IDEStateTools.swift`, test MCP integrato in `Tests/CoderEngineTests/MCPSessionManagerTests.swift`.
- Non-scope: pipeline UI della review chat, mapping eventi sintetici, flusso main chat agent.
- Moduli confinanti da verificare: normalizzazione tool MCP, pipeline subagent, session manager MCP.
- Test da aggiungere o aggiornare: test integrato che chiama `coderide_subagent_explorer` sul binario `coderide-mcp-server` e verifica ack immediato/non errore.
- Strategia di fix minimo: aggiungere `subagent_*` all'insieme dei tool pass-through e validare `task` nello stesso handler IDE-state.
- Verifica post-fix: test MCP dedicato con timeout client corto; controllo del routing esistente della pipeline subagent.
- Commit previsto: `fix(review-chat): avoid MCP timeout for subagent launches`
