# 2026-03-12 — Rust MCP server tranche 1

## Modifiche
- introdotto workspace Cargo in `Native/` con:
  - `AppCoreProtocol`
  - `CoderideMCPServerRust`
  - `RustCore`
- aggiunto crate Rust `app_core_protocol` con:
  - envelope JSON-RPC
  - tipi MCP per `initialize`, `tools/list`, `tools/call`
- aggiunto binario Rust `coderide-mcp-server-rust` con:
  - transport stdio newline-delimited compatibile con il client Swift MCP locale
  - handshake `initialize`
  - supporto `tools/list`
  - supporto `tools/call` per:
    - `coderide_read`
    - `coderide_list_dir`
    - `coderide_glob`
    - `coderide_grep`
    - `coderide_todo_read`
    - `coderide_todo_write`
    - ack IDE state
    - ack subagent
    - bridge minimo review/security/bughunter verso `RustCore`
- `RustCore` ora esporta anche `rlib` e rende pubblico `review_mcp` per il riuso da parte del nuovo server Rust
- aggiunto script `scripts/build_rust_mcp_server.sh`
- aggiornati `scripts/build-app.sh` e `scripts/run-app.sh` per:
  - costruire il binario MCP Rust
  - copiarlo nel bundle
  - rifirmare il bundle dopo la copia
- aggiornato `scripts/validate_app_bundle.sh` per verificare anche:
  - `Contents/MacOS/coderide-mcp-server`
  - `Contents/MacOS/coderide-mcp-server-rust`
- `Tools/CoderIDEMCPServerExecutable/Sources/CoderIDEMCPServerExecutableMain.swift` ora supporta l’exec del sibling Rust con gate esplicito:
  - `SOLOCODE_USE_RUST_MCP_SERVER=1`

## Validazione eseguita
- `cargo test --manifest-path Native/CoderideMCPServerRust/Cargo.toml`
- `./scripts/build_rust_mcp_server.sh`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests -only-testing:CoderEngineTests/ToolEnabledLLMProviderMCPWarmupTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPSessionManagerTests/testCallToolRichRecordsMetrics -only-testing:CoderEngineTests/MCPSessionManagerTests/testSubagentExplorerToolReturnsImmediateAck`
- smoke test bundle:
  - copy binario Rust nel bundle debug
  - `codesign --force --deep`
  - `scripts/validate_app_bundle.sh`

## Esito
- esiste ora un server MCP Rust separato, buildabile e testato
- i test engine che parlano con `coderide-mcp-server` tramite processo esterno restano verdi
- il bundle app può includere il sibling Rust senza rompere la validazione
- il cutover totale del launcher resta bloccato da parità tool incompleta ed è documentato come bug aperto P1
