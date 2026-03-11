# 2026-03-11 - Sidebar restore + Postgres test isolation tranche

## Modifiche
- aggiunto un `SidebarView` compatibile con il call site di `ContentView+Layout+Composition`, senza reimportare il vecchio sidebar completo
- separato il supporto sidebar in:
  - [SidebarView.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/SidebarView.swift)
  - [SidebarView+Support.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/SidebarView+Support.swift)
  - [SidebarView+DeletionFallback.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/SidebarView+DeletionFallback.swift)
- aggiunto [SidebarViewTests.swift](/Users/benjaminstoica/SoloCode/Tests/SoloCodeAppTests/SidebarViewTests.swift) per la costruzione base della view
- resa test-aware la configurazione Postgres di default in [PersistenceModels.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/PersistenceModels.swift)
- aggiornato [ManagedPostgresService.swift](/Users/benjaminstoica/SoloCode/Engine/CoderEngine/Sources/PersistenceCore/ManagedPostgresService.swift) per leggere gli override environment anche con l’istanza shared
- isolato root/porta temporanei dei test in [PersistenceTestSupport.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Persistence/PersistenceTestSupport.swift)
- aggiunto test di regressione configurazione in [PersistenceSchemaTests.swift](/Users/benjaminstoica/SoloCode/Tests/CoderEngineTests/Persistence/PersistenceSchemaTests.swift)
- ristretto [bootstrap_test_bundles.sh](/Users/benjaminstoica/SoloCode/scripts/bootstrap_test_bundles.sh) ai soli bundle `.xctest` e allineata la rifirma ai flag usati da Xcode

## Verifica
- il build app-side non cade più sui simboli sidebar mancanti (`SidebarView`, fallback thread helpers)
- il test Postgres mirato non cade più su data dir sporca in `Application Support`
- resta un’instabilità separata del run completo `Solo Code-Debug` e del loader `xctest` in alcuni giri `test-without-building`, non più attribuibile alla data dir condivisa
