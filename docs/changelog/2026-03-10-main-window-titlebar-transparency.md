# 2026-03-10 - Main window titlebar transparency

- Documentato il problema visuale in [P2-2026-03-10-main-window-titlebar-band-not-transparent.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-10-main-window-titlebar-band-not-transparent.md).
- Aggiornato [AppDelegate.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/AppDelegate.swift) per usare il background AppKit della sidebar come riempimento della finestra.
- Aggiornato [AppDelegate.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/AppDelegate.swift) per nascondere i semafori nativi Apple mantenendo attiva la finestra macOS sottostante.
- Aggiornato [ContentView+Layout+Composition.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Content/Sections/ContentView+Layout+Composition.swift) per tornare a un container sidebar custom e impedire alla `NavigationSplitView` di reinserire il toggle flottante nativo.
- Aggiornato [WindowSidebarToggleController.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Utilities/WindowSidebarToggleController.swift) per ripristinare il vecchio pulsante custom e continuare a ripulire il chrome nativo indesiderato.
- Aggiornato [SidebarView+Layout.swift](/Users/benjaminstoica/SoloCode/Sidebar/SidebarView+Layout.swift) per rimuovere il toggle temporaneo dalla fascia top della sidebar e lasciare lì solo i semafori custom.
- Aggiornato [AppDelegateWindowStyleTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/AppDelegateWindowStyleTests.swift) per coprire background sidebar e hiding dei semafori nativi.
- Validazione eseguita: `xcodebuild build -scheme 'Solo Code-Debug'` e `xcodebuild test -scheme 'Solo Code-Debug' -only-testing:SoloCodeAppTests/AppDelegateWindowStyleTests` completati con successo.
