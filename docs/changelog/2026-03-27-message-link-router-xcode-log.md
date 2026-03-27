# Changelog — 2026-03-27 — MessageLinkRouter e link `x-xcode-log`

## Categoria

B — Integrazione macOS / UX chat

## Problema

I link esterni nei bubble chat e nel markdown inline usavano `OpenURLAction.systemAction` per tutto ciò che non era `file://`. Gli URL con schema `x-xcode-log://` (tipici dei riferimenti al log Xcode) non avevano un percorso esplicito verso `NSWorkspace`, con rischio di click inefficace o incoerente sul desktop.

## Modifiche

| File | Descrizione |
|------|-------------|
| `App/SoloCodeApp/Sources/Utilities/MessageLinkRouter.swift` | Nuovo router: `file://` → callback editor; `http`/`https`/`mailto`/`x-xcode-log` → `NSWorkspace.shared.open`; altri schemi → `.discarded` |
| `App/SoloCodeApp/Sources/Chat/ClickableMessageContent.swift` | `OpenURLAction` delegato a `MessageLinkRouter.open` |
| `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Renderers.swift` | Stesso wiring per il markdown inline |
| `Tests/SoloCodeAppTests/MessageLinkRouterTests.swift` | Test su disposition (file, x-xcode-log, javascript rifiutato) |

## Documentazione

- `docs/bugs/P2-2026-03-27-chat-click-x-xcode-log-not-opened.md`
- `docs/bugfix-records/2026-03-27-x-xcode-log-link-routing.md`

## Verifica

```bash
xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" \
  -destination 'platform=macOS' \
  -only-testing:SoloCodeAppTests/MessageLinkRouterTests \
  -only-testing:SoloCodeAppTests/MarkdownFileReferenceLinkingTests
```

## Note sicurezza

La allowlist degli schemi esterni evita aperture involontarie per schemi pericolosi (es. `javascript:`) partendo da contenuto modello/markdown.
