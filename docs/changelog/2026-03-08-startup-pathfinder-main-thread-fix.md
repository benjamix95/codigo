# 2026-03-08 - Startup crash fix per PathFinder sul main thread

- Documentato il crash di avvio in [P0-2026-03-08-app-startup-crash-main-thread-pathfinder.md](/Users/benjaminstoica/SoloCode/docs/bugs/P0-2026-03-08-app-startup-crash-main-thread-pathfinder.md).
- Aggiornato [PathFinder.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/Workspace/PathFinder.swift) per impedire la lookup shell interattiva quando il chiamante è sul main thread.
- Aggiunto il test di regressione [PathFinderTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/PathFinderTests.swift) per coprire il caso main-thread.
- Lasciata invariata la lookup shell nei contesti background, così la detection CLI continua a funzionare fuori dal bootstrap UI.
