# P2 - 2026-03-21 - Codex MCP todo batch parser accepted structured object payloads

## Bug Fix Record
- Categoria: B
- Bug: il parser condiviso dei `todos` batch accettava un oggetto strutturato nativo nel campo `todos`, invece di richiedere una collezione batch valida.
- Sintomo: nel path Codex stream parser un `mcp_tool_call` `todo_write` con `status=failed` e `arguments.todos` oggetto singolo produceva `mcp_tool_call_failed` invece di `invalid_todos_payload`.
- Impatto: classificazione errore incoerente tra parser stream, runtime unificato e server MCP; rischio di nascondere payload batch invalidi dietro un errore generico.
- Gravità: media.
- Steps to reproduce:
  1. Eseguire `CodexCLIProviderStreamParsingTests/testParseStreamJSONEventEmitsTodoValidationErrorOnFailedMCPStatus`.
  2. Inviare un evento `item.completed` con `mcp_tool=coderide_todo_write`, `status=failed`, `arguments={"todos":{"content":"not-array"}}`.
- Risultato attuale: `tool_validation_error.error_code == mcp_tool_call_failed`.
- Risultato atteso: `tool_validation_error.error_code == invalid_todos_payload`.
- Causa probabile: `IDEStateTodoArgumentParser.parse` normalizzava qualsiasi `[String: Any]` come singolo todo valido; i callsite batch del campo `todos` riusavano questa semantica permissiva.
- Scope consentito: parser condiviso `IDEStateTodoArgumentParser`, callsite batch `todo_write`, test Codex/UnifiedToolRuntime/MCP server.
- Non-scope: routing provider, plan tools, persistence, UI chat, altri parser non collegati a `todos`.
- Moduli confinanti da verificare: Codex CLI stream parsing, UnifiedToolRuntime MCP IDE-state events.
- Test da aggiungere o aggiornare:
  - riproduzione esistente `CodexCLIProviderStreamParsingTests/testParseStreamJSONEventEmitsTodoValidationErrorOnFailedMCPStatus`
  - nuova regressione `UnifiedToolRuntimeTests/testSyntheticIDEStateEventsFromMCPRejectsStructuredJSONObjectTodosPayload`
- Strategia di fix minimo: introdurre una entrypoint batch più stretta (`parseBatchCollection`) che continui ad accettare array, checklist e stringhe JSON legacy, ma rifiuti oggetti strutturati nativi nel campo `todos` nei path stream/runtime.
- Verifica post-fix:
  - test singolo Codex stream parser verde
  - suite mirata UnifiedToolRuntime verde
  - suite providers mirata verde
- Commit previsto: `fix(providers): reject structured object todos batch payloads`
