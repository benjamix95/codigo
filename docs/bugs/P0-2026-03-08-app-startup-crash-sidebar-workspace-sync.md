# P0 - Crash avvio app per sync sidebar durante il layout iniziale SwiftUI

## Bug Fix Record
- Categoria: A - Critico
- Bug: l'app andava in crash all'avvio quando la sidebar sincronizzava `ProjectContextStore` e `WorkspaceStore` durante il primo pass di layout SwiftUI.
- Sintomo: crash `SIGSEGV`/AttributeGraph su thread principale con top frame in `SidebarView.body.getter` durante il bootstrap della finestra principale.
- Impatto: crash immediato all'avvio, impossibilità di entrare nell'app.
- Gravità: critica
- Steps to reproduce:
  1. Avviare l'app macOS con almeno un workspace/context persistito.
  2. Lasciare che la sidebar venga costruita al primo render.
  3. Osservare il crash nella catena `SidebarView` -> layout SwiftUI/AttributeGraph.
- Risultato attuale: `sidebarContent` eseguiva mutazioni sincrone di store osservati in `.onAppear` e `.onChange`, chiamando `ensureWorkspaceContexts(...)` e `syncActiveWorkspace(...)` nel mezzo del render iniziale.
- Risultato atteso: la sidebar deve completare il layout iniziale senza mutare store osservati nello stesso pass; la sync workspace/context deve avvenire nel tick successivo del main run loop.
- Causa probabile: mutazione re-entrante di stato osservato da SwiftUI durante la costruzione iniziale della view, con instabilità di AttributeGraph.
- Scope consentito: `App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarView+Sections+Core.swift`, documentazione bug/changelog.
- Non-scope: refactor della sidebar, restyling UI, redesign dell'ownership tra `ProjectContextStore` e `WorkspaceStore`, fix ai flussi account/router non direttamente coinvolti nel crash confermato.
- Moduli confinanti da verificare: `SidebarView`, `ProjectContextStore`, `WorkspaceStore`, sincronizzazione contesto attivo, bootstrap finestra principale.
- Test da aggiungere o aggiornare: smoke test manuale di avvio reale dell'app; tentativo di regressione automatizzata nel target `SoloCodeAppTests` non affidabile nell'ambiente corrente per problemi di discovery/codesign del bundle test.
- Strategia di fix minimo: differire le mutazioni store in una helper dedicata chiamata da `.onAppear` e `.onChange`, eseguendole con `DispatchQueue.main.async`.
- Verifica post-fix:
  1. `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/PathFinderTests`
  2. Smoke test avvio app con `open -n` del bundle buildato e controllo assenza di nuovi `.ips`
  3. Verifica utente: app avviata correttamente senza crash
- Commit previsto: `fix(startup): defer sidebar workspace sync`
