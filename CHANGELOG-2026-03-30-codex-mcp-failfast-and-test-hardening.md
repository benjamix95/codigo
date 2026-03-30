# Changelog — 2026-03-30 — Codex MCP fail-fast and test hardening

## Obiettivo

Blindare il flusso Codex oltre il solo provisioning del binario MCP, in modo che una regressione futura non possa più passare “verde” mentre `coderide` è rotto o non esposto.

## Modifiche applicate

### 1. Fail-fast sullo startup MCP di `coderide`
- Nuovo file: `Native/RustCore/src/main_chat/providers/cli/codex_app_server_mcp_status.rs`
- Estrae e normalizza le notifiche `mcpServer/startupStatus/updated`.
- Se `coderide` entra in `failed`, il transport Codex produce errore esplicito invece di proseguire fail-open.
- `codex_app_server.rs` ora emette anche un raw event `codex_mcp_server_status` per il trace.

### 2. Parser locale dei config Codex allineato al profilo hardenizzato
- File: `Engine/CoderEngine/Sources/Infrastructure/MCP/Config/Parsing/MCPConfigLoader+CodexParsing.swift`
- Il parser strict ora accetta e ignora in modo esplicito:
  - `required`
  - `tool_timeout_sec`
  - `enabled`
- Risultato: niente warning rumorosi quando il profilo Codex usa il nuovo blocco `mcp_servers.coderide`.

### 3. Copertura test ampliata su più livelli
- `Tests/CoderEngineTests/MCPConfigLoaderParsingTests.swift`
  - nuovo test per `required`, `tool_timeout_sec`, `enabled`
- `Tests/CoderEngineTests/CodexCLIProviderInvocationTests.swift`
  - nuovo test che garantisce la preservazione del flag `required = true`
- `Native/RustCore/src/main_chat/providers/cli/codex_app_server_mcp_status.rs`
  - test Rust su parsing, normalizzazione payload e fail-fast solo per `coderide`

## Effetto pratico

- Se `coderide` fallisce lo startup MCP, Codex non degrada più silenziosamente ai tool built-in.
- Il path locale che legge `config.toml` Codex è allineato al profilo hardenizzato e non produce warning fuorvianti.
- La copertura non è più confinata al solo resolver del binario: ora protegge provisioning, parser config e comportamento del transport Codex quando il server MCP si rompe.

## Suite eseguite

- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/MCPConfigLoaderParsingTests -only-testing:CoderEngineTests/CodexCLIProviderInvocationTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/CLIProfileProvisionerTests`
- `cargo test --manifest-path Native/RustCore/Cargo.toml parse_startup_status_reads_name_status_and_error -- --nocapture`
- `cargo test --manifest-path Native/RustCore/Cargo.toml required_failure_only_triggers_for_failed_coderide -- --nocapture`
