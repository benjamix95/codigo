# P2 - Main window: la fascia superiore della title bar resta opaca

## Bug Fix Record
- Categoria: Categoria B — importante ma non bloccante
- Bug: la fascia superiore della finestra principale non si integrava con la sidebar e i semafori nativi Apple continuavano a imporre un chrome non coerente.
- Sintomo: nella parte alta dell'app compariva una banda continua piatta; inoltre il toggle sidebar nativo/temporaneo compariva in alto a destra mentre il toggle custom corretto non era più nella sua posizione originale.
- Impatto: degrado UX e incoerenza con il chrome macOS atteso; la window appare più pesante e meno integrata con il contenuto sottostante.
- Gravità: P2
- Steps to reproduce:
  1. Avviare l'app macOS.
  2. Aprire la finestra principale in una modalità con pannelli visibili.
  3. Osservare la banda superiore sotto i semafori della finestra.
- Risultato attuale: il chrome nativo Apple manteneva la banda superiore e il toggle sidebar poteva riapparire in alto a destra, separato dal resto del chrome custom.
- Risultato atteso: la fascia superiore deve risultare integrata solo con la sidebar; i semafori nativi devono sparire, la sidebar deve arrivare fino in alto e il vecchio toggle custom deve restare l'unico toggle visibile.
- Causa probabile: confermata. `NavigationSplitView` reintroduceva il toggle nativo di macOS, mentre il passaggio ai controlli custom aveva duplicato il toggle anche dentro la sidebar.
- Scope consentito:
  - [AppDelegate.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/AppDelegate.swift)
  - [ContentView+Layout+Composition.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Content/Sections/ContentView+Layout+Composition.swift)
  - [SidebarView+Layout.swift](/Users/benjaminstoica/SoloCode/Sidebar/SidebarView+Layout.swift)
  - [WindowSidebarToggleController.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Utilities/WindowSidebarToggleController.swift)
  - [AppDelegateWindowStyleTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/AppDelegateWindowStyleTests.swift)
- Non-scope: refactor del layout SwiftUI generale oltre al container della sidebar, modifiche ai pannelli chat/browser/IDE, redesign dei contenuti sidebar oltre alla fascia top.
- Moduli confinanti da verificare: apertura finestra principale, toolbar unificata macOS, resa dei pannelli con aree top drag-safe.
- Test da aggiungere o aggiornare: nessun harness snapshot/UI automatico locale per il chrome AppKit della finestra; validazione tramite build e scenario manuale ripetibile.
- Strategia di fix minimo: allineare il `backgroundColor` della `NSWindow` al colore sidebar, nascondere i semafori nativi Apple, tornare al layout sidebar senza `NavigationSplitView` per evitare il toggle nativo flottante, rimuovere il toggle temporaneo interno alla sidebar e ripristinare il vecchio pulsante custom in title bar.
- Verifica post-fix:
  1. Build macOS dello scheme `Solo Code-Debug`.
  2. Test mirato `SoloCodeAppTests/AppDelegateWindowStyleTests`.
  3. Scenario manuale: verificare che i semafori nativi non siano più visibili, che il toggle flottante in alto a destra sia sparito e che resti solo il vecchio toggle custom.
- Commit previsto: `fix(window): restore sidebar-only chrome controls`
