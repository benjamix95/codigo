# 2026-03-10 — Sincronizzazione finalizzazione swarm tra snapshot chat e store live

## Modifiche
- aggiunto `finalizedSwarmCardSnapshotForTaskCompletion(...)` in `TaskActivityStore`
- lo snapshot finale continua a leggere `activities + pendingActivities`
- lo store live viene flushato e finalizzato al tick successivo, evitando publish reentranti ma riallineando i pannelli live

## Test
- aggiunto `testFinalizedSwarmSnapshotAlsoFinalizesLiveStoreCards`

## Rischio controllato
- il transcript finale e le viste live convergono sullo stesso stato `completed`
