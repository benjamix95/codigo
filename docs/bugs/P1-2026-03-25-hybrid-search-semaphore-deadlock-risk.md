# P1 — HybridSearchEngineBackend: Rischio Deadlock da Semaphore Blocking

**Data**: 2026-03-25
**Categoria**: B — Importante
**Scope**: Engine/CoderEngine/Sources/CodebaseIndex/Indexing/HybridSearchEngineBackend.swift

---

## Bug

`HybridSearchEngineBackend.mergeWithVectorSync()` usa `DispatchSemaphore.wait()` per bridgare codice async → sync, con timeout 500ms.

## File e righe

`HybridSearchEngineBackend.swift:74-88`

```swift
let semaphore = DispatchSemaphore(value: 0)
Task.detached { [weak self] in
    // async vector search...
    semaphore.signal()
}
_ = semaphore.wait(timeout: .now() + 0.5)
```

## Problema

Se questo codice viene eseguito su un executor di un actor Swift (e.g. `SemanticIndex` è un actor), il `semaphore.wait()` blocca il thread. Se il `Task.detached` ha bisogno dello stesso cooperative thread pool, rischio di thread starvation o deadlock.

## Impatto

- Deadlock intermittente sotto carico (molte ricerche parallele)
- Timeout 500ms mitiga ma non elimina — in caso di thread starvation il Task.detached potrebbe non partire entro 500ms

## Fix proposto

Rendere il protocollo `SearchEngineBackend.search()` async, eliminando la necessità del semaphore bridge:

```swift
public protocol SearchEngineBackend: Sendable {
    func search(query: SearchQueryInput, snapshot: SemanticIndexSearchSnapshot) async -> SearchEngineBackendResponse
}
```
