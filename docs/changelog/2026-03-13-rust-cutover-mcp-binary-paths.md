# 2026-03-13 - Rust cutover MCP binary paths

## Modifiche
- aggiornati i path di provisioning CLI per usare `coderide-mcp-server-rust` come sibling path e fallback assoluto
- aggiornati `MCPSessionManager` e i test MCP per riconoscere il binario Rust come comando canonico
- rimosso dall’artifact script MCP la copia dell’alias legacy `coderide-mcp-server`
- aggiornata `validate_app_bundle.sh` per richiedere solo il binario Rust MCP
- trasformato `CoderIDEMCPServerApp.main()` in fail-fast esplicito del runtime Swift legacy

## Validazione
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS'`: verde
- `xcodebuild build -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS'`: verde

## Impatto
- il repo smette di trattare `coderide-mcp-server` come nome canonico del runtime MCP
- il launcher e i profili gestiti convergono sul binario Rust, riducendo i path legacy ancora riattivabili
