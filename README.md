# CoderIDE

Native Cursor-like IDE for macOS built in Swift, with an integrated AI assistant ("Coder") that supports multiple LLM providers.

## Features

- **Coder**: integrated AI assistant in the chat panel
- **Multiple providers**: OpenAI API, Codex CLI, Claude Code CLI
- **Workspace**: open folders and send file context to Coder
- **MCP**: Model Context Protocol support (Swift SDK)
- **History**: persistently saved conversations

## Requirements

- macOS 14+ (Sonoma)
- Xcode 16+ (Swift 5.9/6)

## Installation

```bash
cd codigo
swift build
swift run Codigo
```

**Voice input (microphone):** Speech recognition TCC requires an app bundle. Use:

```bash
./build-app.sh
open Codigo.app
```

## Configuration

1. **OpenAI API**: Set your API key in Settings (gear icon)
2. **Codex CLI**: Install with `brew install codex`, then use "Login Codex" in Settings
3. **Claude Code CLI**: Install from [claude.com/code](https://claude.com/code)

## Structure

- `CoderEngine/`: library with LLM providers, MCP, and shared protocols
- `Sources/CoderIDE/`: macOS SwiftUI app

## Providers

| Provider      | Auth                      | Notes                          |
|---------------|---------------------------|--------------------------------|
| OpenAI API    | API Key                   | `gpt-4o-mini` (default)        |
| Codex CLI     | `codex login` or API key  | Requires Codex installation    |
| Claude CLI    | Claude Code configuration | `claude -p` in headless mode   |
