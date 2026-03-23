## Bug Fix Record
- Categoria: A - Critico
- Bug: il main chat Codex usava `codex exec --json`, che non forniva un client `tool_call_suggested` compatibile con il runtime tool del progetto e lasciava Codex dipendere dai propri tool interni.
- Sintomo: Codex risultava autenticato e con MCP configurato, ma nel main chat continuava a usare `command_execution`/tool interni invece dei tool di progetto.
- Impatto: impossibilità di garantire l’uso dei tool `coderide_*` e dei flussi `todo/plan/debug` richiesti dal progetto.
- Gravità: P1
- Steps to reproduce:
  1. Selezionare `codex-cli` nel main chat.
  2. Eseguire un task che richiede `read`, `todo_write` o `plan_*`.
  3. Osservare che il provider usa `command_execution` o tool interni invece dei tool MCP di progetto.
- Risultato attuale: `codex exec` non espone un client tool/runtime adeguato al main chat.
- Risultato atteso: il main chat Codex deve usare `codex app-server`, che vede `coderide_*` come tool MCP nativi del profilo gestito.
- Causa probabile: il transport Codex nel provider Rust era ancorato al path `exec` e il gate Swift bypassava ancora il transport Rust quando il runtime tool unificato era attivo.
- Scope consentito:
  - `Native/RustCore/src/main_chat/providers/cli/codex.rs`
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server.rs`
  - `Native/RustCore/src/main_chat/providers/cli/codex_app_server_support.rs`
  - `Native/RustCore/src/main_chat/providers/cli/mod.rs`
  - `App/SoloCodeApp/Sources/Chat/Support/Providers/Rust/RustMainChatProviderFactory.swift`
  - test mirati correlati
- Non-scope:
  - refactor di Claude/Gemini/OpenAI
  - dynamic tools client completi per tool custom non-MCP
- Moduli confinanti da verificare:
  - risoluzione transport Rust main chat
  - provider Codex Rust
  - eventi `mcp_tool_call` / `todo` / `plan` / `debug`
- Test da aggiungere o aggiornare:
  - regressione su bypass transport Codex
  - compile/smoke Rust provider path
- Strategia di fix minimo:
  - sostituire il path `codex exec` con `codex app-server` nel provider Rust Codex
  - mantenere il main chat Codex sul transport Rust, senza bypass
  - tradurre le notifiche app-server in eventi compatibili con il resto dell’app
- Verifica post-fix:
  - compile `solocode_rust_core`
  - test Swift mirati su provider factory/runtime selection
  - smoke con `codex app-server` e `coderide_*`
- Commit previsto:
  - fix(codex): migrate main chat transport to app-server
