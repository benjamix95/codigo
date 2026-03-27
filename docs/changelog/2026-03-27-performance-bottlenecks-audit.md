# 2026-03-27 — Audit colli di bottiglia performance

## Cosa ho fatto

- analizzato i path caldi di:
  - indice semantico
  - semantic search
  - bridge chat Swift↔Rust
  - pipeline integration
  - root view SwiftUI della chat
- eseguito il benchmark selettivo gia' presente nel repository per l'indice;
- eseguito un harness Swift locale collegato al framework `CoderEngine` gia' buildato per avere numeri sintetici ripetibili su 300 file.

## Benchmark raccolti

- dataset: `300` file Swift sintetici;
- mediane su 3 run:
  - full indexing: `1327 ms`
  - incremental indexing: `79 ms`
  - semantic search: `436 ms`
- run osservati:
  - full indexing: `[1323, 1341, 1327]`
  - incremental indexing: `[79, 77, 84]`
  - semantic search: `[517, 436, 352]`

## Finding principali confermati

- `semantic_search` ha ancora un costo strutturale alto perche' serializza tutto lo snapshot dell'indice a ogni query prima di chiamare Rust;
- `ChatPanelView` resta un nodo SwiftUI troppo osservante: molti `@EnvironmentObject`, molti `@State` e wrapper pass-through che mantengono ampio il dependency graph;
- il bridge `ChatStore` ↔ Rust continua a lavorare a snapshot completi invece che a delta locali;
- `PipelineIntegrationService` continua a pubblicare snapshot completi sul main actor;
- `TodoStore.saveTodos()` e `EventBus.publish()` hanno ancora overhead ricorrenti nei path interattivi.

## Documentazione creata

- bug audit: [ARCH-2026-03-27-performance-bottlenecks-audit.md](/Users/benjaminstoica/SoloCode/docs/bugs/ARCH-2026-03-27-performance-bottlenecks-audit.md)

## Verifica

- test selettivo indice: passato
- audit statico path caldi: completato
- nessuna modifica runtime applicata in questo passaggio
