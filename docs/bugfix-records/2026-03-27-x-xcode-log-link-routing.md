# Bug Fix Record — 2026-03-27 — Routing link `x-xcode-log` dalla chat

- Categoria: B — Integrazione macOS / Xcode
- Bug: i link `x-xcode-log://…` nei messaggi non erano gestiti in modo esplicito nel `OpenURLAction` della chat e del markdown inline.
- Sintomo: click sul link del log Xcode dalla UI chat senza apertura affidabile del target IDE.
- Impatto: interruzione del flusso “condividi / riapri log” tra Xcode e Solo Code.
- Gravità: media-alta per sviluppatori che alternano editor e Xcode.
- Steps to reproduce:
  1. Inserire in chat testo che contenga un URL `x-xcode-log://<UUID>`.
  2. Cliccare il link reso cliccabile dal renderer markdown/AttributedString.
- Risultato attuale (pre-fix): dipendenza da `systemAction` generico per URL non file.
- Risultato atteso: `NSWorkspace.shared.open(url)` per `http`, `https`, `mailto`, `x-xcode-log`; `file://` resta interno tramite `onFileClicked`.
- Causa probabile: assenza di router centralizzato e allowlist di schemi sicuri / IDE.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Utilities/MessageLinkRouter.swift`
  - `App/SoloCodeApp/Sources/Chat/ClickableMessageContent.swift`
  - `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+Renderers.swift`
  - `Tests/SoloCodeAppTests/MessageLinkRouterTests.swift`
- Strategia di fix minimo:
  - nuovo modulo `MessageLinkRouter` con `disposition(for:)` e `open(_:onFileClicked:)` `@MainActor`
  - sostituzione del corpo `OpenURLAction` nelle due view citate
- Test aggiunti:
  - `MessageLinkRouterTests`: file URL, `x-xcode-log`, `javascript:` respinto
- Verifica post-fix:
  - test mirati `MessageLinkRouterTests` + `MarkdownFileReferenceLinkingTests` (regressione link file)
- Riferimento bug strutturato:
  - `docs/bugs/P2-2026-03-27-chat-click-x-xcode-log-not-opened.md`
