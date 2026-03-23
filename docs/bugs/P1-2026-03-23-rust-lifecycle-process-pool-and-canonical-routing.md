## Bug Fix Record
- Categoria: A - Critico
- Bug: il boundary MCP `coderide` continuava a duplicare ownership e processi tra lifecycle Rust e runtime Swift, con due sintomi concreti: 1) server configurazioni duplicate potevano generare piu' child process equivalenti, 2) i tool canonici restavano Swift-owned finche' non erano inclusi in una whitelist manuale.
- Sintomo:
  - processi `coderide-mcp-server-rust` multipli per la stessa identita' operativa effettiva;
  - tool canonici come `write`, `grep`, `todo_write`, `plan_create`, `review_start`, `debug_session`, `web_search` non passavano automaticamente a Rust o perdevano il marker MCP nei payload IDE-state anche con alias `coderide_*` gia' registrato.
- Impatto: regressioni di stabilita' sul lifecycle MCP, rischio di `Transport closed`/process churn, e ownership ibrida del path standard dei tool.
- Gravita': P1
- Steps to reproduce:
  1. Registrare due server MCP equivalenti con stesso comando/args/cwd ma ID diversi.
  2. Forzare `reconnect`/`call_tool` sui due alias.
  3. Osservare child process duplicati o boot count divergente.
  4. Scaldare `MCPNativeToolRegistry` con `coderide_write` o `coderide_web_search`.
  5. Eseguire il nome canonico `write` o `web_search`.
- Risultato attuale:
  - il lifecycle backend indicizzava i child per `server.id`, non per identita' operativa condivisibile;
  - `UnifiedToolRuntime` preferiva Rust solo per una whitelist manuale e validava localmente prima del reroute MCP;
  - i synthetic IDE-state events derivati da MCP non propagavano sempre `is_mcp` e `tool` canonico per `review_start`, `todo_write`, `plan_create`.
- Risultato atteso:
  - un solo processo condiviso per stessa identita' operativa `command + args + cwd + env`;
  - i tool canonici Rust-owned devono preferire l'alias `coderide_*` appena il registry e' caldo.
- Causa probabile:
  - pooling processi assente nel lifecycle backend Rust;
  - gate Swift basato su whitelist manuale e posizione sbagliata della validazione locale.
- Scope consentito:
  - `Native/MCPLifecycleBackendRust/src/*`
  - `Engine/CoderEngine/Sources/Infrastructure/MCP/RustLifecycle/MCPLifecycleRustModels.swift`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/MCP/Core/UnifiedToolRuntime+MCPCanonicalAliasRouting.swift`
  - `Engine/CoderEngine/Sources/Tools/Runtime/UnifiedToolRuntime/Core/Execution/Dispatch/UnifiedToolRuntime+RunCoreDispatch.swift`
  - test Rust/Swift mirati
- Non-scope:
  - merge tra `mcp-lifecycle-backend-rust` e `coderide-mcp-server-rust`
  - refactor UI/chat/store
  - nuovi server MCP pubblici
- Moduli confinanti da verificare:
  - `MCPSessionManagerRustLifecycleTests`
  - `UnifiedToolRuntimeMCPConsistencyTests`
  - `ToolSchemaCatalogTests`
  - `backend_smoke`
- Test da aggiungere o aggiornare:
  - regressione Rust su riuso del processo per server duplicati
  - regressione Swift su tool canonici che preferiscono `coderide_*`
  - regressione catalogo alias per famiglie Rust-owned
- Strategia di fix minimo:
  - introdurre pooling processi nel lifecycle backend Rust, condividendo i child per chiave operativa;
  - inviare `cwd` canonico dal bridge Swift al lifecycle backend;
  - spostare il reroute Rust prima della validazione Swift e sostituire la whitelist con policy per famiglie/tool Rust-owned;
  - propagare `is_mcp` e `tool` canonico nei synthetic IDE-state payload MCP.
- Verifica post-fix:
  - `cargo test --manifest-path Native/MCPLifecycleBackendRust/Cargo.toml`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --test server_smoke initialize_and_list_tools_work -- --nocapture`
  - `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml --test catalog_contract`
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerRustLifecycleTests -only-testing:CoderEngineTests/UnifiedToolRuntimeMCPConsistencyTests -only-testing:CoderEngineTests/ToolSchemaCatalogTests`
- Commit previsto:
  - `fix(mcp): pool rust lifecycle processes and widen canonical alias routing`
