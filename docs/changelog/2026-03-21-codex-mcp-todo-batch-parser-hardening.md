# 2026-03-21 - Codex MCP todo batch parser hardening

## Changed
- aggiunto `IDEStateTodoArgumentParser.parseBatchCollection` per distinguere il parsing batch del campo `todos` dal parsing permissivo del singolo todo;
- allineati i callsite batch in:
  - `IDEStateSyntheticEventFactory`
  - `UnifiedToolRuntime`
  - `CodexCLIProvider` synthetic events

## Fixed
- corretto il caso in cui un payload MCP `todo_write` con `todos` oggetto strutturato veniva accettato come singolo todo valido;
- ripristinata la classificazione `invalid_todos_payload` nel parser stream Codex quando il batch `todos` è malformato;
- mantenuta la retrocompatibilità per i payload legacy `todos` come stringa JSON oggetto singolo e checklist string.

## Tests
- `CoderEngineTests/CodexCLIProviderStreamParsingTests/testParseStreamJSONEventEmitsTodoValidationErrorOnFailedMCPStatus`
- `CoderEngineTests/UnifiedToolRuntimeTests/testSyntheticIDEStateEventsFromMCPRejectsStructuredJSONObjectTodosPayload`
- suite mirata providers/unified runtime lato macOS via `xcodebuild test`
