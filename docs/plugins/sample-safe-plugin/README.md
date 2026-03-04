# Sample Safe Plugin

Plugin d'esempio per il runtime estensioni minimale.

## Obiettivo

Mostrare un manifest con capability sandbox e tool-safe API.

## Struttura

- `manifest.json`: contratto unificato (`entryPoint`, `exposedTools`, `minimumIDEVersion`).
- `plugin.js`: implementazione con lifecycle `load/unload` e handler tool-safe.

## Note

- Il runtime applica una whitelist derivata da `capabilities`.
- `exposedTools` viene intersecato con tale whitelist.
- `minimumIDEVersion` viene validata in fase di load.
- Alias legacy supportati in decode: `entrypoint` e `allowedTools`.
