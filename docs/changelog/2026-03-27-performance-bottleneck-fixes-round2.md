# 2026-03-27 — Performance bottleneck fixes round 2

## Modifiche

- `CodebaseIndex.addIndexedFile(...)` ora usa set locali per bucket file/nome/kind e smette di fare deduplica lineare ripetuta su array crescenti.
- `PipelineIntegrationService.snapshotsByConversation` non e' piu' `@Published`; restano le notifiche per-conversation tramite `snapshotDidChange`.
- la sidebar ora costruisce `snapshot + fingerprint` e `renderStates + fingerprint` in un solo passaggio ciascuno, evitando compute duplicate.
- il codice render-related della sidebar e' stato spostato in [SidebarThreadRenderState.swift](/Users/benjaminstoica/SoloCode/App/SoloCodeApp/Sources/App/Sidebar/SidebarThreadRenderState.swift) per restare sotto il limite dimensionale dei file.
- la chat separa il refresh del testo dal refresh del chrome runtime: `swarm steps/cards`, `activities` e `pipeline snapshot` non vengono piu' ricalcolati su ogni tick testo.
- la build phase `Sync tool_descriptions Swift` usa ora dependency analysis invece di essere sempre out-of-date.

## Test aggiunti o aggiornati

- `PipelineIntegrationSnapshotPublisherTests`
  - aggiunto controllo che l’update snapshot non emetta piu' `objectWillChange` globale
- `SidebarThreadSnapshotTests`
  - aggiunti test che confrontano i builder combinati con i path legacy
- `CodebaseIndexIncrementalTests`
  - aggiunto test che ri-applicare lo stesso `IndexedFile` non duplichi i simboli

## Verifica eseguita

- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotPublisherTests -only-testing:SoloCodeAppTests/SidebarThreadSnapshotTests`
  - esito: passato
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/CodebaseIndexIncrementalTests/testDuplicateSymbolIDsDoNotInflateCounters -only-testing:CoderEngineTests/CodebaseIndexIncrementalTests/testReaddingIndexedFileDoesNotDuplicateStoredSymbols -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
  - esito: passato

## Note residue

- le phase Rust restano sempre out-of-date: non le ho toccate perche' non hanno ancora input/output affidabili dichiarati e il rischio di build stale e' maggiore del beneficio immediato
- il full scan iniziale del workspace resta un’area da ridurre ulteriormente con un intervento separato sul traversal/index bootstrap
