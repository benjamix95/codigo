# Changelog — 2026-03-27 — Guard del probe Codex sul main thread

## Categoria

A — Stabilità startup / macOS

## Problema

Durante l’avvio il ranking dei path Codex eseguiva `codex --version` in modo sincrono sul main thread. Il `waitUntilExit()` riattivava il run loop e, mentre SwiftUI stava aggiornando `MarkdownContentView`, il processo finiva in `EXC_BAD_ACCESS` su `StreamingCursorView`.

## Modifiche

| File | Descrizione |
|------|-------------|
| `Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/CodexDetector.swift` | aggiunto `allowsBlockingVersionProbe`; `findCodexPath` disabilita il probe della versione quando e' invocato dal main thread e ricade sul primo candidato eseguibile |
| `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+StreamingCursor.swift` | rimossa la `@State` locale e l’animazione perpetua; cursor resa stateless per evitare copy/retain fragile in layout reentrante |
| `Tests/CoderEngineTests/CodexDetectorStablePathTests.swift` | nuova regressione che verifica l’assenza di chiamate al `versionLoader` quando il probe bloccante e' disabilitato |

## Documentazione

- `docs/bugs/P1-2026-03-27-startup-codex-probe-reentered-markdown-layout-and-crashed.md`
- `docs/bugfix-records/2026-03-27-startup-main-thread-codex-probe-guard.md`

## Verifica

```bash
xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" \
  -destination 'platform=macOS'

xcodebuild test -workspace "Solo Code.xcworkspace" -scheme "CoderEngineTests-Debug" \
  -destination 'platform=macOS' \
  -only-testing:CoderEngineTests/CodexDetectorStablePathTests
```

## Note

Il ranking completo per versione resta attivo fuori dal main thread; il cambiamento contiene solo il path di bootstrap UI per evitare freeze e crash di startup.
