# P1 — Avvio bloccato dal probe Codex sul main thread con crash reentrante nel markdown

## Bug Fix Record

- Priorità: P1
- Categoria: A — Critico (startup / stabilità app)
- Bug: durante l’avvio la costruzione del provider Codex eseguiva il ranking dei path CLI sul main thread, chiamando `codex --version` in modo sincrono. Il `waitUntilExit()` lasciava pompare il run loop e reinnescava layout SwiftUI mentre `MarkdownContentView` stava costruendo il body, fino a un `EXC_BAD_ACCESS` su `StreamingCursorView`.
- Sintomo: l’app si chiudeva all’avvio con `SIGBUS`/`EXC_BAD_ACCESS`; i report mostravano sia `MarkdownContentView.body.getter` / `initializeWithCopy for StreamingCursorView` sia `NSConcreteTask.waitUntilExit` in `CodexDetector.loadCodexVersion(at:)`.
- Impatto: impossibile aprire l’app in debug o via lancio diretto su macOS.
- Gravità: critica.
- Steps to reproduce:
  1. Build dello scheme `Solo Code-Debug`.
  2. Lancio dell’app su macOS.
  3. Durante il bootstrap del provider Codex il main thread entra in `waitUntilExit()`.
  4. Il layout SwiftUI viene rieseguito e il processo cade.
- Risultato attuale (prima del fix): avvio instabile o crash immediato.
- Risultato atteso: l’app si avvia senza bloccare il main thread per il probe della versione Codex; il markdown streaming non deve introdurre stato fragile durante il bootstrap.
- Causa probabile:
  - probe sincrono `codex --version` durante `findCodexPath` su main thread;
  - `StreamingCursorView` con `@State` e animazione perpetua, fragile sotto reentrancy/layout copy in fase di avvio.
- Scope consentito:
  - `Engine/CoderEngine/Sources/ProviderBackends/CodexCLI/CodexDetector.swift`
  - `App/SoloCodeApp/Sources/Editor/Markdown/MarkdownContentView+StreamingCursor.swift`
  - `Tests/CoderEngineTests/CodexDetectorStablePathTests.swift`
  - documentazione `docs/bugs`, `docs/bugfix-records`, `docs/changelog`
- Non-scope:
  - refactor del bootstrap provider
  - redesign completo del renderer markdown
  - ristrutturazione dei flussi account/login CLI
- Moduli confinanti da verificare:
  - `CodexCLIProvider`
  - `ProviderFactory+CLI`
  - `ChatPanelView+PartI_ToolRuntimePolicy`
  - smoke del renderer markdown streaming
- Test da aggiungere o aggiornare:
  - regressione su `CodexDetector.preferredCodexPath` quando il probe bloccante e' disabilitato
- Strategia di fix minimo:
  - disattivare il probe bloccante della versione quando il ranking avviene dal main thread, ricadendo sull’ordine dei candidati eseguibili;
  - rendere `StreamingCursorView` stateless per eliminare il path di copy/retain fragile durante layout reentrante.
- Verifica post-fix:
  - build macOS dello scheme `Solo Code-Debug`
  - test mirato `CodexDetectorStablePathTests`
  - lancio diretto dell’app per verificare che resti viva oltre il bootstrap iniziale
- Commit previsto:
  - `fix(startup): avoid main-thread codex probe during launch`
