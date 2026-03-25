# Changelog — 2026-03-25 — Fix MCPSharedState eager directory creation

## Problema

All'avvio dell'app compariva il warning:

```
[MCPSharedState] ⚠️ Failed to write code review commands: The folder "commands.json" doesn't exist.
```

La directory `code-review/` sotto `mcp-shared/` non veniva creata fino al primo tentativo
di scrittura, causando un errore quando `_writeCodeReviewCommandsUnsafe` tentava di
scrivere `commands.json` prima che la directory esistesse.

## Categoria

**B — Importante ma non bloccante**

Il warning non impediva il funzionamento (la directory veniva creata al retry),
ma generava log fuorvianti e poteva mascherare problemi reali.

## Causa

`ensureDirectory()` creava solo `sharedDirectory` (`mcp-shared/`) ma non la
sottodirectory `codeReviewDirectoryPath` (`mcp-shared/code-review/`).
Inoltre, `ensureDirectory()` non veniva chiamata all'avvio dell'app, ma solo
lazily alla prima scrittura di todos o lock.

## Fix applicato

### 1. `MCPSharedState.swift` — `ensureDirectory()` ora crea anche `code-review/`

- Aggiunta creazione di `codeReviewDirectoryPath` oltre a `sharedDirectory`
- Reso `public` per consentire la chiamata dal modulo `SoloCodeApp`

### 2. `AppDelegate.swift` — Chiamata eager all'avvio

- Aggiunta `MCPSharedState.ensureDirectory()` in `applicationDidFinishLaunching`
- Le directory vengono ora create prima di qualsiasi operazione MCP

## File modificati

| File | Modifica |
|------|----------|
| `Engine/CoderEngine/Sources/Infrastructure/MCP/MCPSharedState.swift` | `ensureDirectory()` → `public`, aggiunta creazione `codeReviewDirectoryPath` |
| `App/SoloCodeApp/Sources/App/AppDelegate.swift` | Aggiunta chiamata `MCPSharedState.ensureDirectory()` all'avvio |

## Verifica

- Build compilata con successo (`BUILD SUCCEEDED`)
- Il warning non comparirà più perché la directory esiste già all'avvio
