# 2026-03-23 — Tool label normalization (no `MCP` / no `coderide`)

## Modifiche
- Normalizzati i label utente delle chiamate `mcp_tool_call` per mostrare solo il nome del tool effettivo.
- Rimossi prefissi e wrapper come `MCP call`, `Calling MCP tool`, `Invoking MCP tool`, `coderide_`, `mcp_` e `server/tool`.
- Allineati titolo evento, subtitle live, plan trace e collapsed summary della trace sullo stesso criterio.

## Verifiche
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests -only-testing:SoloCodeAppTests/EventNormalizerLiveStateTests`
- Esito: successo, 49 test eseguiti senza failure.
