# 2026-03-08 - Startup crash fix per sync sidebar workspace/context

- Documentato il crash di avvio in [P0-2026-03-08-app-startup-crash-sidebar-workspace-sync.md](/Users/benjaminstoica/SoloCode/docs/bugs/P0-2026-03-08-app-startup-crash-sidebar-workspace-sync.md).
- Aggiornato [SidebarView+Sections+Core.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/Sections/SidebarView+Sections+Core.swift) per differire la sync `ProjectContextStore`/`WorkspaceStore` fuori dal pass di layout SwiftUI iniziale.
- Introdotta una helper privata che concentra la sync della sidebar e la esegue nel tick successivo del main run loop.
- Verificato l'avvio del bundle macOS buildato senza nuovi crash log `.ips`; conferma utente: l'app ora si apre correttamente.
