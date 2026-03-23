## 2026-03-23 - Codex main chat app-server transport

- Il main chat Codex sul path Rust ora usa `codex app-server` invece di `codex exec --json`.
- Il gate Swift non bypassa più il transport Rust per Codex quando il runtime tool unificato è attivo.
- Il provider Rust Codex traduce le notifiche `app-server` essenziali in eventi compatibili con il main chat, inclusi `mcp_tool_call` e gli eventi sintetici `todo/plan/debug` per i tool MCP di progetto.
