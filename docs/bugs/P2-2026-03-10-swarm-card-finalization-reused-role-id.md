# P2 — Finalizzazione swarm card basata su `swarm_id` riusabile

## Bug Fix Record
- Categoria: B
- Bug: la finalizzazione differita delle swarm card chiudeva il live store per `swarm_id`, anche se nel frattempo era già partito un nuovo turno con lo stesso ruolo.
- Sintomo: una card `planner` / `coder` appena riaperta poteva venire marcata `.completed` dal cleanup del turno precedente.
- Impatto: stato live errato nel pannello task/swarm e snapshot chat fuorviante sul turno successivo.
- Gravità: media
- Steps to reproduce:
  1. Chiudere un turno con una card `planner` ancora `running`.
  2. Prima che il `DispatchQueue.main.async` di finalizzazione venga eseguito, emettere un nuovo evento `planner`.
  3. Il cleanup del turno precedente finalizza la card del turno nuovo.
- Risultato attuale: il cleanup differito usava solo l'insieme degli `swarmId`.
- Risultato atteso: la finalizzazione deve verificare che la card live corrisponda ancora alla snapshot del turno chiuso.
- Causa probabile: uso di `swarm_id` stabile per ruolo (`planner`, `coder`, ecc.) senza marker di turno nel passo di finalize differito.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - redesign del reducer swarm
  - modifica del formato degli eventi provider
- Moduli confinanti da verificare:
  - `ChatPanelView+PartE_TaskLifecycle.swift`
  - `SwarmWorkerRunner.swift`
- Test da aggiungere o aggiornare:
  - regressione con riuso dello stesso `swarm_id` in due turni consecutivi
- Strategia di fix minimo:
  - finalizzare il live store solo se `startedAt`, `lastEventAt` e ultimo evento coincidono ancora con la snapshot congelata
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- Commit previsto: `fix(tasking): finalize only matching swarm turn snapshots`

## Evidenza
- il test nuovo riusa lo stesso `swarm_id` (`planner`) nel turno successivo e verifica che, dopo il finalize differito, la card live resti `running`
