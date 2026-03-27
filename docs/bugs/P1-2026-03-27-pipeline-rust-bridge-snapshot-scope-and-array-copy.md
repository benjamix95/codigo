# P1 — 2026-03-27 — Pipeline Rust bridge snapshot scope e array copy evitabile

## Priorità

- P1

## Bug trovati

1. **Snapshot pipeline troppo ampio nel seed iniziale e nel path legacy**
   - Il boundary Rust della pipeline continuava a costruire snapshot store non confinati al solo thread attivo quando il cache non era ancora popolato o nel path legacy `applyPipelineEvent/applyPipelineEvents`.
   - Effetto: costo di serializzazione crescente con dimensione dello store, anche quando il delta riguardava un solo assistant message.
   - Stato: **fixato**.

2. **Update scoped che riassegnava ancora l’intero array `conversations`**
   - `applyScopedForPipeline(...)` aggiornava una sola conversazione ma passava comunque da una nuova copia dell’intero array prima della riassegnazione.
   - Effetto: costo lineare evitabile, pressione COW e invalidazione più larga del necessario.
   - Stato: **fixato**.

## Fix applicati

- Aggiunto snapshot scoped riusabile per pipeline e boundary Rust.
- Il runtime pipeline ora riusa cache scoped quando disponibile e, al miss, serializza solo la conversazione attiva e gli eventuali plan board correlati.
- Il path legacy `RustMainChatStoreAdapter.applyPipelineEvent(s)` ora usa anch’esso stato scoped.
- Aggiunto helper `ChatStore.upsertConversationFromScopedRustBridge(...)` per aggiornare/appendere la conversazione target senza rebuild completo dell’array.

## Verifica

- Test mirati bridge/pipeline eseguiti con successo.
- Nessuna failure sui boundary tests Rust/UI coinvolti.
