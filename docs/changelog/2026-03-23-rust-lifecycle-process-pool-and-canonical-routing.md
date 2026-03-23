## 2026-03-23 - Rust lifecycle process pool and canonical alias routing

- Il backend `mcp-lifecycle-backend-rust` ora condivide i child process MCP equivalenti tramite una chiave operativa basata su `command + args + cwd + env`, invece di spawnare un processo separato per ogni `server.id`.
- Il bridge Swift verso il lifecycle backend passa ora un `cwd` canonico, cosi' le entry con `--workspace .` vengono deduplicate in modo stabile dentro lo stesso workspace.
- `UnifiedToolRuntime` prova ora il reroute MCP Rust prima della validazione locale quando esiste un alias `coderide_*` per una famiglia/tool Rust-owned.
- Il gate `preferredRustAliasRoute` non e' piu' limitato al vecchio sottoinsieme minimo: copre famiglie core (`todo_*`, `plan_*`, `debug_*`, `review_*`, `security_*`, `bughunter_*`, `audit_*`, `subagent_*`) e tool canonici file/search/web rilevanti (`read`, `write`, `edit`, `grep`, `glob`, `list_dir`, `find_*`, `codebase_search`, `semantic_search`, `web_*`, `git_diff`, `skill`, `policy_ack`, `activate_*`).
- I synthetic IDE-state events generati da chiamate MCP ora propagano anche `is_mcp` e `tool` canonico, cosi' `review_start`, `todo_write` e `plan_create` restano riconoscibili come MCP-backed fino alla UI e ai test.
- Aggiunte regressioni:
  - Rust lifecycle su riuso del processo per configurazioni server duplicate;
  - Swift runtime su preferenza MCP per tool canonici rappresentativi, inclusi `review_start`, `todo_write` e `plan_create` lato payload/event mapping;
  - catalogo alias per famiglie Rust-owned.
- Corretto anche un compile blocker preesistente in `Native/CoderideMCPServerRust/src/debug_tools.rs`, che impediva la validazione del server Rust.

### Validazione eseguita
- Verde:
  - `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --test server_smoke initialize_and_list_tools_work -- --nocapture`
- In corso o da confermare nel momento di questo changelog:
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --test catalog_contract`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerRustLifecycleTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/ToolSchemaCatalogTests`

### Note
- Il contratto MCP pubblico resta invariato: un solo server logico `coderide`, nessun rename e nessuna nuova entry MCP pubblica.
- Il merge tra `mcp-lifecycle-backend-rust` e `coderide-mcp-server-rust` resta esplicitamente fuori da questa tranche.
