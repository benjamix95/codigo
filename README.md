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
./Scripts/build-app.sh
open Codigo.app
```

## Configuration

1. **OpenAI API**: Set your API key in Settings (gear icon)
2. **Codex CLI**: Install with `brew install codex`, then use "Login Codex" in Settings
3. **Claude Code CLI**: Install from [claude.com/code](https://claude.com/code)

## Rilascio e aggiornamenti

La prima versione pubblicata è `1.0.0`.

- Versione app: `CFBundleShortVersionString` + `CFBundleVersion` in `App/SoloCodeApp/Sources/Info.plist`
- Manifest aggiornamenti: `docs/update/manifest.json`
- Note tecniche per versione: `docs/release-notes/<version>.md`

Per creare una nuova release:

```bash
./scripts/release.sh --version 1.0.1 --build 2 --download-url "https://github.com/benjamix95/codigo/releases/download/v1.0.1/Codigo.app.zip"
```

Per una build firmata in modo production (CLI):

```bash
CODESIGN_IDENTITY="Developer ID Application: NOME (TEAMID)" \
NOTARIZE=true \
NOTARY_KEY_PATH="/percorso/AuthKey_ID.p8" \
NOTARY_KEY_ID="ABC123DEF4" \
NOTARY_ISSUER_ID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
./scripts/release.sh --version 1.0.1 --build 3 --download-url "https://github.com/benjamix95/codigo/releases/download/v1.0.1/Codigo.app.zip"
```

In alternativa (modalità Apple ID/App Password):

```bash
CODESIGN_IDENTITY="Developer ID Application: NOME (TEAMID)" \
NOTARIZE=true \
NOTARY_APPLE_ID="you@example.com" \
NOTARY_APP_PASSWORD="@keychain:AC_PASSWORD" \
NOTARY_TEAM_ID="TEAMID" \
./scripts/release.sh --version 1.0.1 --build 3 --download-url "https://github.com/benjamix95/codigo/releases/download/v1.0.1/Codigo.app.zip"
```

Note:
- `NOTARIZE=false` (default): solo firma (o ad-hoc se non disponibile).
- `NOTARIZE=true`: richiede credenziali notarization e firma con certificato Developer ID.
- Se non hai `NOTARY_*`, la build fallisce prima di generare il pacchetto.

Lanciando lo script verranno aggiornati automaticamente:
- Info.plist con versione/build
- `docs/update/manifest.json`
- pacchetto `.app` e zip in `dist/Codigo-<version>.app.zip` (tramite `./Scripts/build-app.sh`)

## Structure

- `CoderEngine/`: library with LLM providers, MCP, and shared protocols
- `App/SoloCodeApp/Sources/`: macOS SwiftUI app

## Providers

| Provider      | Auth                      | Notes                          |
|---------------|---------------------------|--------------------------------|
| OpenAI API    | API Key                   | `gpt-4o-mini` (default)        |
| Codex CLI     | `codex login` or API key  | Requires Codex installation    |
| Claude CLI    | Claude Code configuration | `claude -p` in headless mode   |
