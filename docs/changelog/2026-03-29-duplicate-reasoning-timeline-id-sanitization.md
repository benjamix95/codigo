# Changelog — 2026-03-29

## Chat Timeline
- Sanitizzati gli `id` duplicati dei blocchi timeline, in particolare sui blocchi `reasoning`.
- I segmenti reasoning della timeline hanno ora una difesa aggiuntiva sull’identità per evitare warning `ForEach` e rendering indefiniti.

## Snapshot / Persistence
- `resolvedTimelineBlocks` e `ChatTurnState.blocks` ora restituiscono blocchi con identità coerenti anche quando il sorgente contiene più segmenti reasoning.
