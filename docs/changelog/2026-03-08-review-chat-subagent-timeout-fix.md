# 2026-03-08 — Review chat subagent timeout fix

## Modifiche
- trattati i tool `subagent_*` come IDE-state pass-through nel server `coderide-mcp-server`
- aggiunta validazione del parametro `task` per i launch subagent via MCP
- aggiunto test di regressione che chiama `coderide_subagent_explorer` sul binario MCP e verifica ack immediato

## Motivazione
- nella chat di code review il primo launch subagent restava bloccato nel runtime MCP fino al timeout, impedendo il flusso di bug hunting e review parallela

## Verifica
- esecuzione del test mirato `MCPSessionManagerTests/testSubagentExplorerToolReturnsImmediateAck`
