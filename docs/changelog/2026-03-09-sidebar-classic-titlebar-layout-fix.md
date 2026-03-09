# 2026-03-09 - Sidebar classic titlebar layout fix

- Documentato il bug visuale in [P2-2026-03-09-sidebar-classic-titlebar-layout.md](/Users/benjaminstoica/SoloCode/docs/bugs/P2-2026-03-09-sidebar-classic-titlebar-layout.md).
- Documentato separatamente il problema preesistente della suite integration in [P1-2026-03-09-integration-test-bundle-missing-executable.md](/Users/benjaminstoica/SoloCode/docs/bugs/P1-2026-03-09-integration-test-bundle-missing-executable.md).
- Rimossa la fascia header vuota dalla sidebar in [SidebarView+Sections+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarView+Sections+Core.swift).
- Spostato l'inset superiore dentro il contenuto scrollabile della sidebar per mantenere il contenuto sotto i semafori senza creare un box top separato.
- Perimetro volutamente confinato alla sidebar standard; nessuna modifica al toggle custom della colonna o al chrome AppKit della finestra.
- Validazione eseguita: `xcodebuild build` sullo scheme `Solo Code-Debug` completato con successo; `xcodebuild test` sullo scheme `Solo Code-IntegrationTests` bloccato da bundle test non caricabile, non dal fix della sidebar.
