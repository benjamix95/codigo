# Changelog - 2026-03-29 - Subagent panel and spinner clarity

## Modifiche

- la strip inline `LIVE SUBAGENTS` mostra ora solo i sub-agent `running`
- i sub-agent finiti compaiono in una sezione separata nella strip
- il panel sub-agents separa overview attiva e finished
- il titolo del panel usa `sub-agents`
- l’icona della sezione/group sub-agents è stata resa più “robotica” (`cpu.fill`)
- `SpinningDottedCircle` non usa più `circle.dotted`: ora gira più veloce e con un pattern di dash meno fitto

## Test

- aggiunto `SwarmCardPresentationPartitionTests`
- rieseguiti:
  - `ChatTimelineInterleavingSubagentTests`
  - `ChatTurnCompletedSubagentsGroupPresentationTests`
  - `SwarmCardPresentationPartitionTests`
