# CoderIDE

IDE Cursor-like nativo in Swift per macOS, con un assistente AI ("Coder") che supporta multipli provider LLM.

## Funzionalità

- **Coder**: assistente AI integrato nel pannello chat
- **Provider multipli**: OpenAI API, Codex CLI, Claude Code CLI
- **Workspace**: apertura cartelle, contesto file inviato al Coder
- **MCP**: supporto Model Context Protocol (SDK Swift)
- **Cronologia**: conversazioni salvate in modo persistente

## Requisiti

- macOS 14+ (Sonoma)
- Xcode 16+ (Swift 5.9/6)

## Installazione

```bash
cd codigo
swift build
swift run CoderIDE
```

## Configurazione

1. **OpenAI API**: Imposta la tua API key in Impostazioni (icona ingranaggio)
2. **Codex CLI**: Installa con `brew install codex`, poi "Login Codex" nelle impostazioni
3. **Claude Code CLI**: Installa da [claude.com/code](https://claude.com/code)

## Struttura

- `CoderEngine/`: libreria con provider LLM, MCP, protocolli
- `Sources/CoderIDE/`: app macOS SwiftUI

## Provider

| Provider      | Auth                      | Note                          |
|---------------|---------------------------|-------------------------------|
| OpenAI API    | API Key                   | gpt-4o-mini (default)        |
| Codex CLI     | `codex login` o API key   | Richiede Codex installato    |
| Claude CLI    | Config Claude Code        | `claude -p` in modalità headless |
