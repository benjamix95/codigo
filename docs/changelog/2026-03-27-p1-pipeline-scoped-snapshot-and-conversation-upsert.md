# Changelog — P1 Pipeline scoped snapshot e conversation upsert

**Data:** 2026-03-27
**Categoria:** Performance — P1

## Problema

Il path pipeline della main chat aveva ancora due costi evitabili:

- costruzione di snapshot store più ampi del necessario nel seed iniziale e nel path legacy;
- update scoped che riassegnava l’intero array `conversations` anche quando cambiava una sola conversazione.

## Fix

- Introdotto `RustMainChatStoreAdapter.scopedSnapshot(...)` e relativo `scopedPipelineUIState(...)`.
- Il runtime `PipelineIntegrationService` usa snapshot scoped e riusa il cache scoped già restituito dal boundary Rust.
- Il path legacy `applyPipelineEvent(...)` e `applyPipelineEvents(...)` usa ora stato scoped.
- `ChatStore` espone `upsertConversationFromScopedRustBridge(...)` per aggiornare solo la conversazione target mantenendo la notifica throttled.
- Splittati i file grossi toccati:
  - `RustMainChatStoreAdapter.swift` + `RustMainChatStoreAdapter+Pipeline.swift`
  - `PipelineIntegrationService+ChatPipeline.swift` + `PipelineIntegrationService+RustBoundary.swift`

## File modificati

- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter.swift`
- `App/SoloCodeApp/Sources/Chat/Support/StoreRust/RustMainChatStoreAdapter+Pipeline.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+ChatPipeline.swift`
- `App/SoloCodeApp/Sources/Services/ChatPipeline/Runtime/PipelineIntegrationService+RustBoundary.swift`
- `App/SoloCodeApp/Sources/Services/ChatStore/Core/ChatStoreCore.swift`
- `Tests/SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests.swift`

## Verifica

- `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/RustMainChatStoreAdapterScopedApplyTests -only-testing:SoloCodeAppTests/RustMainChatUIBoundaryTests -only-testing:SoloCodeAppTests/PipelineIntegrationServiceTests`
- Risultato: **18 test, 0 failure**

## Impatto atteso

- meno serializzazione bridge nei batch pipeline;
- meno copie dell’array `conversations`;
- percorso legacy allineato al boundary runtime ottimizzato;
- moduli toccati riportati sotto la soglia dimensionale richiesta.
