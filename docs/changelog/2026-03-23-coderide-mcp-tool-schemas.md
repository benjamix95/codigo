## 2026-03-23 - Coderide MCP tool schemas

- Il server MCP Rust `coderide` ora pubblica schema input concreti per i tool core invece di esportare sempre un oggetto vuoto.
- Aggiunto supporto schema per file/search/edit/todo/plan/debug/panel/subagent/skill/web tool principali.
- Aggiunto test di contratto sul catalogo MCP per verificare che `coderide_read`, `coderide_todo_write` e `coderide_plan_create` espongano parametri reali.
