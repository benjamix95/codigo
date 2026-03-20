## 2026-03-20

- aggiunta una regola dedicata in [solocode-validate](/Users/benjaminstoica/SoloCode/scripts/solocode-validate) per `Chat/Support/StoreRust/*` e `ChatStoreStreaming`
- il validator ora seleziona:
  - `SoloCodeAppTests/ChatStoreTaskOwnershipTests`
  - `SoloCodeAppTests/ChatStoreStreamingTargetTests`
- evitato il fallback all'intera suite `SoloCodeAppTests` per una tranche `main chat` confinata allo store runtime
