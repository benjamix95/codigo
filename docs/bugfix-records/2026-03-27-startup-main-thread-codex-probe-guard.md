# Bug Fix Record — 2026-03-27 — Guard sul probe Codex durante l’avvio

- Categoria: A — Startup / stabilità macOS
- Bug: il bootstrap del provider Codex eseguiva un probe `--version` sincrono sul main thread per ordinare i path candidati, causando reentrancy del run loop e crash durante il layout del markdown streaming.
- Sintomo: `EXC_BAD_ACCESS`/`SIGBUS` all’avvio con stack che incrocia `MarkdownContentView.body`, `initializeWithCopy for StreamingCursorView` e `CodexDetector.loadCodexVersion(at:)`.
- Impatto: l’app non riusciva a restare aperta oltre i primi secondi di startup.
- Gravità: critica.
- Steps to reproduce:
  1. `xcodebuild build -workspace "Solo Code.xcworkspace" -scheme "Solo Code-Debug" -destination 'platform=macOS'`
  2. Lancio del binario `.app`
  3. osservazione del crash in startup
- Risultato attuale (pre-fix): blocco del main thread in `waitUntilExit()` e crash reentrante.
- Risultato atteso: fallback immediato al primo path eseguibile quando il ranking avviene sul main thread; cursor view innocua e stateless.
- Causa probabile: chiamata esterna bloccante nel path di bootstrap UI + cursor view con stato animato in un albero SwiftUI rientrante.
- Scope consentito:
  - `Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/CodexDetector.swift`
  - `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+StreamingCursor.swift`
  - `Tests/CoderEngineTests/CodexDetectorStablePathTests.swift`
- Strategia di fix minimo:
  - nuovo flag interno `allowsBlockingVersionProbe` in `preferredCodexPath`
  - `findCodexPath` disattiva il probe se chiamato dal main thread
  - `StreamingCursorView` resa stateless e senza animazione
- Test aggiunti:
  - `testPreferredCodexPathSkipsVersionProbeWhenBlockingProbeIsDisabled`
- Verifica post-fix:
  - build macOS dello scheme debug
  - test mirato `CodexDetectorStablePathTests`
  - lancio diretto dell’app oltre la fase iniziale di bootstrap
- Riferimento bug strutturato:
  - `docs/bugs/P1-2026-03-27-startup-codex-probe-reentered-markdown-layout-and-crashed.md`
