# P2 - La policy todo-first bloccava la discovery MCP nativa prima della prima todo

## Bug Fix Record
- Categoria: B - Importante ma non bloccante
- Bug: la chat trattava `list_mcp_resources` e `list_mcp_resource_templates` come esecuzioni operative soggette a `todo_first_required`; i nomi canonicali interni `mcp_list_resources` e `mcp_list_prompts` restavano esposti allo stesso rischio.
- Sintomo:
  - compariva `[Policy error] Emit coderide_todo_write before starting real execution with 'list_mcp_resources'.`
  - la discovery iniziale dei tool MCP nativi falliva prima di qualsiasi lavoro reale.
- Impatto: impediva il bootstrap corretto della sessione quando il primo passo era la ricognizione delle risorse MCP disponibili.
- Gravita': P2
- Steps to reproduce:
  1. Aprire una nuova sessione chat.
  2. Fare eseguire `list_mcp_resources` come prima tool call.
  3. Osservare il blocco `Todo required before execution`.
- Risultato attuale: la funzione `isTodoGatedOperationalTool` non classificava i tool di resource listing come discovery non mutativa.
- Risultato atteso: sia gli alias nativi (`list_mcp_resources`, `list_mcp_resource_templates`) sia i nomi canonicali interni (`mcp_list_resources`, `mcp_list_prompts`) devono essere permessi senza todo iniziale, come gli altri tool di discovery.
- Causa probabile: whitelist incompleta dei tool non mutativi nella policy UI chat.
- Nota 2026-03-23: oltre alla whitelist, il gate era fragile rispetto a varianti del nome tool emesse dal runtime, incluse forme namespaced (`functions.*`), payload camelCase (`mcpTool`) e tipi evento diretti.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Services/ChatThread/ChatPanelSupport+Core.swift`
  - `Tests/SoloCodeAppTests/ChatTodoVisibilityTests.swift`
- Non-scope:
  - runtime MCP server
  - store todo
  - provider prompt/policy lato modello
- Moduli confinanti da verificare:
  - altri tool di discovery MCP non mutativi
  - visibilita' errori policy nella chat lineare
- Test da aggiungere o aggiornare:
  - `ChatTodoVisibilityTests`
- Strategia di fix minimo:
  - aggiungere `list_mcp_resources`, `list_mcp_resource_templates`, `mcp_list_resources` e `mcp_list_prompts` alla whitelist dei discovery tool che non richiedono todo.
  - normalizzare anche forme namespaced e chiavi payload alternative usate dal tracciamento UI/runtime.
- Verifica post-fix:
  - regression test dedicato in `ChatTodoVisibilityTests`
- Commit previsto:
  - `fix(chat): allow native mcp resource discovery before todo`
