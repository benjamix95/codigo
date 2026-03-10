# P1 — Finalizzazione swarm del turno precedente applicata al turno successivo

## Bug Fix Record
- Categoria: A
- Bug: la finalizzazione differita delle swarm card poteva colpire anche card running del turno successivo nella stessa conversation.
- Sintomo: aprendo un nuovo run subito dopo `endTask()`, la prima card live del nuovo turno poteva comparire già `completed` e collassata.
- Impatto: stato live del pannello attività incoerente rispetto al run corrente.
- Gravità: alta
- Steps to reproduce:
  1. Creare una swarm card running.
  2. Chiamare `finalizedSwarmCardSnapshotForTaskCompletion(...)`.
  3. Prima che il callback differito venga eseguito, aggiungere una nuova swarm card running nella stessa conversation.
- Risultato attuale: il path differito finalizzava genericamente le running card della conversation.
- Risultato atteso: vanno finalizzate solo le card catturate nello snapshot del turno appena chiuso.
- Causa probabile: callback asincrono schedulato per conversation, non per insieme di `swarmId` congelati.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - redesign completo di `SwarmLiveReducer`
  - refactor del task activity store
- Moduli confinanti da verificare:
  - `TaskActivityStoreSwarmCardsTests`
  - snapshot live del completion flow
- Test da aggiungere o aggiornare:
  - regressione sul caso “old turn completed / new turn still running”
- Strategia di fix minimo:
  - catturare gli `swarmId` presenti nello snapshot finale
  - finalizzare solo quel set dopo il flush differito
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- Commit previsto: `fix(task-activity): confine swarm finalization to captured cards`

## Evidenza
- il nuovo test verifica che la card del turno precedente vada `completed` mentre quella del turno successivo resti `running`
