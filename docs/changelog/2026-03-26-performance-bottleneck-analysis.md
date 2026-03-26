# Changelog — 2026-03-26 — Analisi Performance Bottlenecks

## Cosa è stato fatto
- Analisi completa dei colli di bottiglia dell'app su 3 macro-aree:
  1. **Pipeline Chat + Rendering** (PipelineIntegrationService, ChatPanelView, RustBridge)
  2. **Engine Concurrency + Memory** (EventBus, SemanticIndex, HybridSearch, FFI)
  3. **UI SwiftUI + Data Flow** (ChatPanelView, store dependencies, re-render cascade)

## Bottleneck trovati: 12 totali
- **1 P0** (critico): DispatchSemaphore in HybridSearchEngineBackend blocca cooperative thread pool → rischio deadlock
- **5 P1** (importanti): SemanticIndex full-persist, recalcAvgDocLength O(n), evict sort O(n log n), ChatPanelView re-render cascade, RustBridge full-serialize su ogni evento
- **6 P2** (moderati): PipelineService @Published, EventBus sequential delivery, firstIndex O(n) ripetuto, SequenceGenerator actor overhead, NSLock non profilati, rootLayout store access in body

## File prodotti
- `docs/bugs/ARCH-2026-03-26-performance-bottlenecks-analysis.md` — report completo con file, righe, impatto e fix suggeriti per ogni bottleneck

## Nessun codice modificato
Questa è un'analisi di sola lettura. I fix saranno implementati in task separati per priorità.
