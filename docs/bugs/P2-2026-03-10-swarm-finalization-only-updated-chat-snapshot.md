# P2 — Finalizzazione swarm applicata solo allo snapshot chat e non allo store live

## Bug Fix Record
- Categoria: B
- Bug: la chiusura del task finalizzava le swarm card solo nella copia salvata nel messaggio chat, lasciando lo store live in stato `.running`.
- Sintomo: `SwarmPanelView`, `TaskActivityPanel` e le altre viste live potevano continuare a mostrare subagent in esecuzione anche dopo `endTask()`.
- Impatto: stato UI incoerente tra transcript finale e pannelli live.
- Gravità: media
- Steps to reproduce:
  1. Accodare una swarm card running nel `TaskActivityStore`.
  2. Terminare il task padre prima di ricevere un evento terminale del subagent.
  3. Leggere sia lo snapshot chat sia `swarmCardStates()`.
- Risultato attuale: lo snapshot chat risultava completed, ma lo store live poteva restare running.
- Risultato atteso: il snapshot finale deve restare non reentrante, ma lo store live deve essere finalizzato al tick successivo.
- Causa probabile: rimozione della chiamata a `finalizeRunningSwarmCards(...)` dal path di completion.
- Scope consentito:
  - `App/SoloCodeApp/Sources/Tasking/Stores/TaskActivityStore+Query.swift`
  - `App/SoloCodeApp/Sources/Chat/Support/Extensions/ChatPanelView+PartE_TaskLifecycle.swift`
  - `Tests/SoloCodeAppTests/TaskActivityStoreSwarmCardsTests.swift`
- Non-scope:
  - refactor completo del pipeline swarm
  - redesign del pannello attività
- Moduli confinanti da verificare:
  - `TaskActivityStoreSwarmCardsTests`
  - `SwarmPanelView`
  - `TaskActivityPanel`
- Test da aggiungere o aggiornare:
  - regressione su snapshot finalized che sincronizza anche le live card nello store
- Strategia di fix minimo:
  - spostare la costruzione dello snapshot finale in un helper del `TaskActivityStore`
  - schedulare flush + `finalizeRunningSwarmCards(...)` sul tick successivo del main queue
- Verifica post-fix:
  - `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- Commit previsto: `fix(swarm): sync live card finalization after task completion`

## Evidenza
- il nuovo test verifica che lo snapshot ritornato sia `completed` e che lo store live converga a `completed` dopo il tick schedulato
