# Changelog — P1 Pipeline Store Snapshot Cache (BOTTLENECK-06)

**Data:** 2026-03-26
**Categoria:** Performance — P1
**Bottleneck ID:** BOTTLENECK-06

## Problema

`RustMainChatStoreAdapter.applyPipelineEvents()` serializzava **tutte** le conversazioni
(`store.conversations.map(conversationSnapshot)`) su **ogni singolo evento pipeline** durante
lo streaming. Con N conversazioni e M messaggi totali, questo era O(N×M) per ogni text delta —
potenzialmente centinaia di volte al secondo.

## Fix

Aggiunto `cachedStoreSnapshot` a `PipelineConversationRuntime`:

- **Prima chiamata:** costruisce lo snapshot dal ChatStore (una sola volta)
- **Chiamate successive:** riusa il cached snapshot dalla risposta Rust precedente
- **Invalidazione:** su `retargetAssistantMessage()`, teardown, e failure Rust

### File modificati

| File | Modifica |
|------|----------|
| `PipelineIntegrationServiceModels.swift` | Aggiunta proprietà `cachedStoreSnapshot: MainChatStoreSnapshotBridge?`, invalidazione in `retargetAssistantMessage()` |
| `PipelineIntegrationService+ChatPipeline.swift` | `applyPipelineEventsThroughRustBoundary` e `applyPipelineEventThroughRustBoundary` ora costruiscono `MainChatUIStateBridge` direttamente con cached snapshot invece di delegare a `RustMainChatStoreAdapter.applyPipelineEvents()` |

## Impatto

- Elimina serializzazione O(N×M) ripetuta su ogni evento pipeline
- Il primo evento paga il costo di serializzazione; i successivi sono O(1) (riuso cache)
- La cache è auto-aggiornata dalla risposta Rust → sempre consistente con lo stato applicato
- Zero rischio di stale data: invalidazione esplicita su retarget/teardown/failure

## Stato bottleneck P1 complessivo

| ID | Stato |
|----|-------|
| BOTTLENECK-02 (persist full rewrite) | ✅ Fixato — persist incrementale con delta files |
| BOTTLENECK-03 (recalcAvgDocLength O(n)) | ✅ Fixato — O(1) con totalTokenCount |
| BOTTLENECK-04 (evictIfNeeded sort O(n log n)) | ✅ Fixato — findOldestChunks bounded min-heap |
| BOTTLENECK-05 (ChatPanelView re-renders) | ⚠️ Parziale — state containers + snapshot caching in place; fix completo richiede migrazione @Observable |
| BOTTLENECK-06 (store serialization per event) | ✅ Fixato — cached store snapshot in pipeline runtime |
