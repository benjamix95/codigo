# 2026-03-10 — Finalizzazione swarm card ancorata alla snapshot del turno

## Modifiche
- `finalizedSwarmCardSnapshotForTaskCompletion(...)` applica ora il finalize live solo se la card corrente coincide ancora con la snapshot del turno chiuso
- il matching usa marker stabili del turno (`startedAt`, `lastEventAt`, ultimo evento) per non chiudere un nuovo `planner`/`coder`
- aggiunta regressione dedicata sul riuso dello stesso `swarm_id` in due turni consecutivi

## Test
- `xcodebuild test -workspace 'Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS,arch=arm64' -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests`
- esito: `TEST SUCCEEDED`

## Rischio controllato
- nessun cambio al reducer swarm
- nessuna modifica agli event payload provider-side
