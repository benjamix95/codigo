# Changelog — 2026-03-30 — Codex MCP provisioning handshake fix

## Problema

Codex aveva regredito all'uso dei tool built-in (`command_execution`, `list_mcp_resources`, `list_mcp_resource_templates`) invece di usare `coderide_*`. Il problema non era nel prompt: il server MCP `coderide` falliva l'handshake su `codex app-server`, ma la sessione proseguiva comunque senza tool MCP esposti.

## Causa radice

Due fattori combinati:

1. Il profilo Codex poteva preferire il binario `.build/rust-mcp-server/debug/coderide-mcp-server-rust` invece del binario cargo canonico `Native/target/debug/coderide-mcp-server-rust`.
2. Il blocco `[mcp_servers.coderide]` era fail-open: senza `required = true`, Codex continuava silenziosamente con i tool built-in quando `coderide` falliva lo startup.

## Modifiche applicate

### 1. Resolver binario MCP Codex
- File: `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+Paths.swift`
- Il resolver non sceglie più il binario solo per timestamp.
- In ambiente sviluppo ora preferisce il binario `Native/target/debug/coderide-mcp-server-rust`.
- Il mirror `.build/...` resta solo fallback.

### 2. Profilo Codex fail-closed su `coderide`
- File: `App/SoloCodeApp/Sources/Accounts/Support/Provisioning/CLIProfileProvisioner+CodexProfiles.swift`
- Il blocco `[mcp_servers.coderide]` generato/riparato ora include:
  - `required = true`
- Il repair di profili esistenti aggiunge o forza il flag durante `environmentOverrides`, `reseedCodexProfile` e self-heal.

### 3. Regression test
- File nuovo: `Tests/SoloCodeAppTests/CLIProfileProvisionerTests+CodexMCPPaths.swift`
- Split dei test path/profilo dal file test principale, che era oversize.
- Nuovo test: preferenza esplicita per `Native/target` anche quando `.build` è più nuova.
- I test di repair del profilo ora verificano anche `required = true`.

## Effetto pratico

- Codex usa di nuovo il binario MCP che completa correttamente l'handshake.
- Se `coderide` non parte, la sessione Codex non degrada più silenziosamente ai tool built-in per il lavoro workspace-critical.
- La regressione resta coperta da test sul provisioning, che era il vero punto di rottura.

## Verifiche eseguite

- Probe `codex app-server`:
  - con path `.build/...` -> `coderide failed` durante lo startup MCP
  - con path `Native/target/...` -> `coderide ready`
- Suite mirata:
  - `SoloCodeAppTests/CLIProfileProvisionerTests`
  - `Native/CoderideMCPServerRust` smoke `initialize_and_list_tools_work`
