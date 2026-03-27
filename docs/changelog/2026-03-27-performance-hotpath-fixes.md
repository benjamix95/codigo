# 2026-03-27 — Performance hotpath fixes

## Modifiche

- `semantic_search` ora puo' riusare il JSON dello snapshot Rust finche' il `simHash` dell'indice non cambia;
- `RustSearchFFIClient` e' stato spezzato in file piu' piccoli (`payload`, `library resolution`, `review bridge`) e il payload builder evita la ricodifica completa dello snapshot nei run successivi;
- `applyRustStoreAction` usa snapshot scoped per le azioni locali su singola conversazione o plan board, invece di serializzare sempre tutto il `ChatStore`;
- aggiunto apply scoped anche sul lato Swift per mantenere solo le conversazioni/board toccate;
- sostituiti lookup lineari frequenti con `conversationIndex(for:)` in fallback Rust, checkpoints, plans e summary helpers;
- `PipelineIntegrationService` e' stato diviso in file piu' piccoli e non aggiorna piu' `snapshotsByConversation` quando lo snapshot e' identico;
- `TodoStore.saveTodos()` ora salta write e sync quando il payload visibile e' invariato e usa encoding stabile con chiavi ordinate.

## Benchmark locale

- dataset sintetico: `300` file Swift;
- `semantic_search` ripetuta sullo stesso indice:
  - prima query: `510 ms`
  - seconda query: `287 ms`
  - terza query: `428 ms`
- interpretazione:
  - il primo hit paga ancora il build del payload cache;
  - dal secondo run si vede la riduzione del costo di serializzazione dello snapshot.

## Verifica

- `swiftlint lint` sui file toccati:
  - nessun errore bloccante dopo il fix
  - restano warning storici/non bloccanti del repository
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'CoderEngineTests-Debug' -destination 'platform=macOS' -only-testing:CoderEngineTests/RustSearchPayloadBuilderTests`
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatScopedStoreActionTests -only-testing:SoloCodeAppTests/TodoStorePersistenceTests -only-testing:SoloCodeAppTests/PipelineIntegrationSnapshotTests`
