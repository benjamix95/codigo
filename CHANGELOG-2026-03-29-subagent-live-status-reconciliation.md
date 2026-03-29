# Changelog - 2026-03-29 - Subagent live status reconciliation

## Modifiche

- reso `SwarmLiveReducer` più robusto nel riconoscere gli stati terminali dei sub-agent anche quando i provider usano valori come `success`, `done`, `ok` o `finished`
- aggiunta una fase di canonizzazione degli eventi swarm che riallinea gli eventi con `swarm_id` diverso ma identità logica uguale alla card live corretta
- spezzato il reducer in file separati:
  - `SwarmLiveReducer.swift`
  - `SwarmLiveReducer+Lifecycle.swift`
  - `SwarmLiveReducer+Identity.swift`
  - `SwarmLiveReducer+Helpers.swift`

## Test

- aggiunti test di regressione in `SwarmLiveReducerTests` per:
  - status terminali non canonici
  - aliasing tra `swarm_id` duplicati
- eseguita validazione mirata:
  - `xcodebuild test -project 'Solo Code.xcodeproj' -scheme 'Solo Code' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SwarmLiveReducerTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`

## Note

- warning esterni di `xcodebuild` relativi a device passcode-protected e linking XCTest non hanno bloccato la suite selezionata
- il fix resta confinato al layer di riduzione stato swarm e non modifica il protocollo eventi dei provider
