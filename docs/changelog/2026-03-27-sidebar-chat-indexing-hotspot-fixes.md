# 2026-03-27 — Sidebar, chat e indexing hotpath fixes

## Modifiche

- sidebar:
  - aggiunti fingerprint cheap per distinguere cambi strutturali dei thread da semplici delta di contenuto;
  - i render state vengono ricalcolati solo quando cambia davvero lo stato visivo dei thread;
  - i task debounce della sidebar vengono cancellati su `onDisappear`;
- chat:
  - introdotto scheduling dedicato per coalescere i refresh completi di `messagesConversationSnapshot`;
  - gli eventi `todoStore` e `taskActivityStore` aggiornano solo lo stato live dipendente, senza rilanciare sempre il refresh completo della conversazione;
  - estratti i modifier di refresh della message area in un file separato per ridurre complessita' e peso del file principale;
- indexing:
  - `buildFileTree(...)` riusa `URL.resourceValues` per metadata file/directory con fallback solo quando necessario;
  - `SemanticIndex` ora persiste il JSONL in streaming su file temporaneo atomico;
  - `SemanticIndex.loadFromDisk()` e applicazione delta leggono le linee in streaming invece di caricare l'intero file come `String`.

## Test

- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SidebarThreadSnapshotTests`
- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/SemanticIndexTests -only-testing:CoderEngineTests/CodebaseIndexIncrementalTests -only-testing:CoderEngineTests/CodebaseIndexIndexingBenchmarkSmokeTests`

## Note

- il worktree conteneva molte modifiche locali non correlate; il fix e' stato confinato solo ai file sopra;
- `xcodebuildmcp` non era disponibile in questa sessione, quindi la validazione macOS e' stata eseguita con `xcodebuild` selettivo;
- restano warning storici del repository e script phase sempre-eseguite (`Sync tool_descriptions Swift`, build Rust) che non bloccano questo fix ma continuano ad aggiungere overhead ai build.
