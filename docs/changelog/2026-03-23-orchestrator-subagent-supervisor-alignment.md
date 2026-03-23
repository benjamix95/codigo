# 2026-03-23 — Orchestrator, supervisor trace e subagent alignment

## Modifiche
- Rimosso il fallback concettuale che trasformava eventi senza owner worker in una card `orchestrator`.
- Introdotti marker payload espliciti per distinguere `owner_kind=worker` e `owner_kind=supervisor` con `supervisor_kind=orchestrator`.
- Tenute le subagent card solo per worker reali; il supervisor non entra più nel reducer delle card.
- Aggiunta una supervisor trace separata nella chat quando esiste un contesto swarm/subagent attivo.
- Allineato il naming UX:
  - worker visibili: `Subagent`
  - supervisor: `Orchestrator`
- Corretto il mapping di presentazione dei ruoli worker, incluso `Planner`.
- Aggiornato l’help di Agent Swarm per spiegare orchestrator supervisor separato, planner come worker distinto e subagent come termine UX.

## Verifiche
- `xcodebuild test -workspace '/Users/benjaminstoica/SoloCode/Solo Code.xcworkspace' -scheme 'Solo Code-Debug' -destination 'platform=macOS' -only-testing:SoloCodeAppTests/SwarmLiveReducerTests -only-testing:SoloCodeAppTests/TaskActivityStoreSwarmCardsTests -only-testing:SoloCodeAppTests/SwarmLivePresentationTests -only-testing:SoloCodeAppTests/PlanShortcutAndCommandTests`
- Esito: successo, 110 test eseguiti senza failure.
