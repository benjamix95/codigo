# 2026-03-09 - Sidebar classic split view fix

- Rimossa la resa a pannello inset della sidebar standard in [ContentView+Layout+Composition.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Content/Sections/ContentView+Layout+Composition.swift) sostituendo lo stile `NavigationSplitView` da `.prominentDetail` a `.balanced`.
- Alzato il contenuto della sidebar in [SidebarView+Sections+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarView+Sections+Core.swift) riducendo l'inset top da `36` a `24`, così quick actions e sezioni partono più vicine ai semafori.
- Aggiornato il bug record in [P2-2026-03-09-sidebar-classic-titlebar-layout.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-09-sidebar-classic-titlebar-layout.md) con la causa reale confermata.
- Validazione prevista: build macOS del workspace e verifica manuale del layout della sidebar con toggle custom.
