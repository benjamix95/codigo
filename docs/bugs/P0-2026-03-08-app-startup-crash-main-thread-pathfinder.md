# P0 - Crash avvio app per lookup CLI bloccante sul main thread

## Bug Fix Record
- Categoria: A - Critico
- Bug: l'app va in crash all'avvio quando una detection CLI esegue `Process.waitUntilExit()` durante la costruzione iniziale del grafo SwiftUI.
- Sintomo: `Thread 1: signal SIGABRT` su `process.waitUntilExit()` in `PathFinder.findUsingInteractiveShell(...)` durante il bootstrap dell'app.
- Impatto: crash immediato all'avvio, impossibilità di usare l'app.
- Gravità: critica
- Steps to reproduce:
  1. Avviare l'app macOS.
  2. Lasciare che il bootstrap iniziale crei `CLIAccountsStore.shared`.
  3. Osservare il crash su `waitUntilExit()` dentro la lookup shell di `PathFinder`.
- Risultato attuale: `CLIAccountsStore.bootstrapAccountsIfNeeded()` può passare da `CLIAccountAuthDetector.resolveExecutable(...)` a `PathFinder.find(...)`, che lancia una shell interattiva e attende in modo sincrono sul main thread.
- Risultato atteso: durante l'avvio l'app non deve mai eseguire `waitUntilExit()` sul main thread; le lookup CLI bloccanti devono essere saltate o demandate a thread di background.
- Causa probabile: `PathFinder.findUsingInteractiveShell(...)` non proteggeva il main thread. In startup questo veniva invocato indirettamente dal bootstrap account, provocando una precondition failure di SwiftUI/AttributeGraph.
- Scope consentito: `Engine/CoderEngine/Sources/Workspace/PathFinder.swift`, test di regressione `Tests/CoderEngineTests/PathFinderTests.swift`, documentazione bug/changelog.
- Non-scope: refactor del bootstrap account, redesign dei flussi auth, refactor generalizzato delle view Settings/Profile.
- Moduli confinanti da verificare: bootstrap `CodigoApp`, `CLIAccountsStore`, resolver CLI Codex/Claude/Gemini, lookup `PathFinder` fuori startup.
- Test da aggiungere o aggiornare: copertura di regressione che verifichi il salto della shell lookup sul main thread.
- Strategia di fix minimo: introdurre un guard in `findUsingInteractiveShell(...)` che ritorna `nil` se chiamato dal main thread, preservando la lookup shell solo nei contesti di background.
- Verifica post-fix:
  1. Test `PathFinderTests.testFindSkipsInteractiveShellLookupOnMainThread`
  2. Smoke test build/test del modulo CoderEngine
  3. Verifica manuale avvio app senza crash
- Commit previsto: `fix(startup): avoid path shell lookup on main thread`
