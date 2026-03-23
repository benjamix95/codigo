# 2026-03-23 — Chat inline trace collapse and tool identity

## Obiettivo

Allineare il trace operativo della chat al formato inline richiesto:

- testo assistente prima;
- trace subito sotto;
- collapse automatico a task finito;
- icone coerenti per `read`, `write`, `search`, `semantic_search` e tool MCP reali.

## Modifiche

- `ChatTurnView` non usa più il feed lineare locale a righe/card-like.
- La chat renderizza `MessageToolTraceView` inline sotto il testo del messaggio.
- `MessageToolTraceView` mostra righe mentre il task è attivo e torna a summary-only a task concluso.
- L’auto-collapse non conserva più forzatamente l’espansione manuale quando il task termina.
- Il mapping delle icone tool è stato centralizzato in `MessageToolTraceView+EventMetadata.swift`.
- Il sommario collassato è stato rifinito in italiano.

## Test

- `MessageToolTraceMCPCamelCaseTests`
- `MessageToolTraceToolIdentityTests`

Comando eseguito:

```bash
xcodebuild test -project '/Users/benjaminstoica/SoloCode/Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/MessageToolTraceMCPCamelCaseTests -only-testing:SoloCodeAppTests/MessageToolTraceToolIdentityTests CODE_SIGNING_ALLOWED=NO
```

Esito: `** TEST SUCCEEDED **`
