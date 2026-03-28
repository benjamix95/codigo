# P1 — Codex continuava a ragionare e riassumere i tool canonici come se non fossero MCP

## Bug Fix Record
- Categoria: B
- Bug: il prompt e il follow-up del provider tool-enabled non rendevano vincolante ne' visibile l'uso dei tool canonici `coderide_*`, anche quando il runtime aveva gia' risolto l'esecuzione via MCP.
- Sintomo: in chat Codex tende a nominare `read` / `grep` / `semantic_search` come tool "di default" e nel riepilogo finale poteva sembrare che nessun MCP fosse stato usato.
- Impatto: percezione errata del runtime, reporting fuorviante a fine task, minore aderenza alla policy di progetto che richiede l'uso dei tool MCP locali.
- Gravita': P1
- Steps to reproduce:
  1. Avviare una sessione tool-enabled con alias `coderide_*` esposti.
  2. Eseguire un task di ispezione workspace (`read`, `grep`, `semantic_search`).
  3. Osservare che il runtime risolve via MCP ma il prompt e il riepilogo continuano a parlare soprattutto di nomi runtime generici.
- Risultato attuale: l'esecuzione puo' passare via MCP, ma il modello non viene guidato in modo abbastanza forte verso il nome canonico `coderide_*` e il follow-up non espone sempre il tool MCP risolto.
- Risultato atteso: il prompt deve preferire esplicitamente i tool `coderide_*` quando disponibili e il follow-up deve conservare `mcp_tool` / server per impedire riepiloghi falsi o ambigui.
- Causa probabile: enforcement esplicito limitato soprattutto all'editing MCP, naming dei prompt ancora runtime-first e riassunto dei risultati che perde metadata MCP risolti.
- Scope consentito:
  - `PromptToolsPolicy`
  - `ToolEnabledLLMProvider+Policy`
  - `ToolEnabledLLMProvider+SummariesAndParsing`
  - `ToolSchemaCatalog+Exports`
  - test prompt/finalization correlati
- Non-scope:
  - refactor del runtime MCP
  - cambi del dispatch di esecuzione gia' funzionante
  - rimozione massiva dei tool runtime generici da tutti i provider
- Moduli confinanti da verificare:
  - prompt standard `SystemPrompts`
  - follow-up prompt multi-round
  - trace/final summary basati su `mcp_tool_call`
- Test da aggiungere o aggiornare:
  - prompt test che verifichi la preferenza `coderide_*`
  - regression test che conservi `mcp_tool` e `mcp_server` nel follow-up prompt
- Strategia di fix minimo:
  - rendere MCP-first i nomi canonici nei prompt
  - preservare metadata MCP risolti nei riassunti dei tool
  - per i provider con function schema, non esportare insieme tool runtime generico e alias `coderide_*` sovrapposti
  - non toccare il dispatch runtime se non necessario
- Verifica post-fix:
  - test mirati su `SystemPromptsTests`
  - test mirati su `ToolEnabledLLMProviderPolicyAckTests+Finalization`
  - test mirati su `ToolSchemaCatalogTests`
- Commit previsto: `fix(prompt): prefer canonical coderide MCP tools in prompts and follow-up summaries`
