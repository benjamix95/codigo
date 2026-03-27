# 2026-03-27 — Performance bottleneck audit round 2

## Cosa ho fatto

- verificato i path runtime piu' costosi nel codice SwiftUI/indexing/pipeline;
- letto il sample reale `.cursor/debug-7e54b6-sample.txt`;
- eseguito benchmark selettivi con `xcodebuild test`:
  - `CoderEngineTests/ValidationPerformanceTests/testSelectorPerformanceOnLargeFileList`
  - `CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
- documentato i colli di bottiglia confermati in `docs/bugs/ARCH-2026-03-27-performance-bottlenecks-round2.md`.

## Finding confermati

- `refreshMessagesSnapshot()` resta troppo ampio e continua a girare sul main path di streaming;
- la sidebar continua a reagire con invalidazione globale a `chatStore.objectWillChange` e rigenera snapshot/render state troppo larghi;
- lo startup resta dominato da `WorkspaceStore.indexActiveWorkspace() -> CodebaseIndex.indexWorkspace(...)`;
- nel sample reale emerge un hotspot concreto in `CodebaseIndex.addIndexedFile(_)`, con costo importante dentro `Sequence.contains(where:)`;
- `PipelineIntegrationService.snapshotsByConversation` resta troppo largo come meccanismo di invalidazione;
- la build phase `Sync tool_descriptions Swift` gira sempre e introduce overhead evitabile nei test/build incrementali.

## Misure ed evidenze

- `ValidationPerformanceTests/testSelectorPerformanceOnLargeFileList`
  - esito: passato
  - media misurata: circa `0.003 s`
- `CodebaseIndexIndexingBenchmarkSmokeTests/testIndexingBenchmarkSmoke`
  - esito: passato
  - log runtime su dataset sintetico default da 40 file:
    - `indexWorkspace: starting full index`
    - `SemanticIndex.buildIndex: completed` in circa `12-13 ms`
- sample reale `.cursor/debug-7e54b6-sample.txt`
  - `3325` sample sotto `WorkspaceStore.indexActiveWorkspace()`
  - `2468` sample dentro `CodebaseIndex.addIndexedFile(_)`
  - `1807` sample figli in `Sequence.contains(where:)`

## Modifiche applicate

- nessuna modifica al runtime applicativo in questo passaggio
- aggiunta sola documentazione di audit e prioritizzazione

## Verifica

- test benchmark selettivi eseguiti con successo
- un primo tentativo parallelo di `xcodebuild` e' fallito per lock del build database; rerun seriale completato con successo
