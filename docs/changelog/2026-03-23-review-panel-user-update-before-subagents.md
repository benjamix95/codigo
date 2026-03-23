# 2026-03-23 — Review panel user update before subagents

## Modifiche
- rimosso l'enforcement hard `subagent_first_required`
- aggiornate le prompt policy per richiedere una frase breve verso l'utente prima del primo round operativo
- mantenuti i subagent come opzione raccomandata per il primo round operativo, ma non piu' come prima azione obbligatoria

## Verifica
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityVisibilityTests -only-testing:CoderEngineTests/MCPSubagentPipelineTests`

## Nota runtime
- ho ricompilato `Native/CoderideMCPServerRust` e terminato i processi `coderide-mcp-server-rust` vecchi per forzare il respawn del backend MCP aggiornato
